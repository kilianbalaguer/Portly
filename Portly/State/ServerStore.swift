import AppKit
import Foundation
import Observation

/// What a row is busy doing, shown in place of its actions.
enum RowActivity: Equatable {
    case stopping
    case forceStopping
    case restarting
}

/// A dismissible message shown above the list.
struct Notice: Identifiable, Equatable {
    let id = UUID()
    var message: String
}

/// One row in the list: a live server, or a server we launched that isn't listening (yet / any more).
enum ServerListItem: Identifiable {
    case server(DevServer, managed: ManagedServer?)
    case pending(ManagedServer)

    var id: String {
        switch self {
        case .server(let server, _): "pid-\(server.pid)"
        case .pending(let managed): "managed-\(managed.id)"
        }
    }

    @MainActor var sortPort: Int {
        switch self {
        case .server(let server, _): server.primaryPort
        case .pending(let managed): managed.expectedPorts.first ?? .max
        }
    }
}

@MainActor
@Observable
final class ServerStore {
    private(set) var servers: [DevServer] = []
    private(set) var managed: [ManagedServer] = []
    private(set) var activity: [Int32: RowActivity] = [:]
    private(set) var notice: Notice?
    private(set) var scanError: String?
    private(set) var hasCompletedFirstScan = false

    var showAll = false
    var searchText = ""

    @ObservationIgnored private let monitor = ServerMonitor()
    @ObservationIgnored private let controller = ProcessController()
    @ObservationIgnored private let scanner = PortScanner()
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    /// Scan interval while the popover is open.
    var openPollInterval: Duration = .seconds(2)
    /// While closed, a slower scan keeps the menu bar count right.
    static let closedPollInterval: Duration = .seconds(10)
    @ObservationIgnored private var popoverOpen = false

    init() {
        LogFiles.removeStale()
    }

    // MARK: - Derived state

    /// What the list shows: dev servers (or everything with "Show all") plus servers we launched
    /// that aren't listening, narrowed by the search and ordered by port.
    var items: [ServerListItem] {
        var items: [ServerListItem] = servers
            .filter { (showAll || $0.isDevServer || managedServer(for: $0) != nil) && $0.matches(searchText) }
            .map { .server($0, managed: managedServer(for: $0)) }
        for entry in managed where !servers.contains(where: entry.owns) && entry.matches(searchText) {
            items.append(.pending(entry))
        }
        return items.sorted { $0.sortPort < $1.sortPort }
    }

    /// Dev servers only; drives the menu bar badge regardless of filters.
    var devServerCount: Int { servers.lazy.filter(\.isDevServer).count }

    /// Listeners hidden by the dev-server filter, for the "N hidden" hint.
    var hiddenCount: Int { showAll ? 0 : servers.count - devServerCount }

    func managedServer(for server: DevServer) -> ManagedServer? {
        managed.first { $0.owns(server) }
    }

    // MARK: - Polling

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                guard let self else { return }
                try? await Task.sleep(for: popoverOpen ? openPollInterval : Self.closedPollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Opening scans immediately and switches to the fast interval; closing drops back to the
    /// slow background scan.
    func setPopoverOpen(_ open: Bool) {
        popoverOpen = open
        if open {
            stop()
            start()
        }
    }

    func refresh() async {
        do {
            let latest = try await monitor.scan()
            // Only assign on change so observers (and the UI) don't churn every tick.
            if latest != servers { servers = latest }
            if scanError != nil { scanError = nil }
        } catch {
            scanError = error.localizedDescription
        }
        for entry in managed where entry.state == .starting && servers.contains(where: entry.owns) {
            entry.state = .running
        }
        hasCompletedFirstScan = true
    }

    // MARK: - Actions

    func open(_ server: DevServer) {
        NSWorkspace.shared.open(server.url)
    }

    func copyURL(_ server: DevServer) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(server.url.absoluteString, forType: .string)
    }

    func kill(_ server: DevServer) {
        guard activity[server.pid] == nil else { return }
        let job = JobResolver.job(for: server)
        let owner = managedServer(for: server)
        owner?.stoppedByUser = true
        Task {
            do {
                try await stopJob(job, rowPID: server.pid)
                if let owner { forget(owner) }
            } catch {
                owner?.stoppedByUser = false
                show(error)
            }
            activity[server.pid] = nil
            await refresh()
        }
    }

    /// Stops the server's job, waits for its port, and relaunches the same command through the
    /// login shell with output captured.
    func restart(_ server: DevServer, then completion: ((ManagedServer) -> Void)? = nil) {
        guard activity[server.pid] == nil else { return }
        let job = JobResolver.job(for: server)
        let owner = managedServer(for: server)
        guard let spec = owner?.spec ?? JobResolver.launchSpec(for: server, job: job) else {
            show(ControlError.notRestartable(reason: server.workingDirectory == nil
                ? "Can't restart \(server.displayName): its working folder is unknown."
                : "Can't restart \(server.displayName): its command line couldn't be read."))
            return
        }
        owner?.stoppedByUser = true
        Task {
            defer { activity[server.pid] = nil }
            do {
                try await stopJob(job, rowPID: server.pid)
                activity[server.pid] = .restarting
                guard await controller.waitForPortToFree(server.primaryPort, scanner: scanner, timeout: .seconds(5)) else {
                    throw ControlError.portStillBusy(server.primaryPort)
                }
                let entry = try await launch(spec, ports: server.ports, name: server.displayName, framework: server.framework, reusing: owner)
                completion?(entry)
            } catch {
                // Still ours if it survived; keep reporting its exit.
                if let owner, ProcessInspector.isAlive(owner.pid) { owner.stoppedByUser = false }
                show(error)
            }
            await refresh()
        }
    }

    /// Restarts a server we launched that has exited.
    func restart(_ entry: ManagedServer) {
        guard entry.state != .starting else { return }
        Task {
            do {
                _ = try await launch(entry.spec, ports: entry.expectedPorts, name: entry.displayName, framework: entry.framework, reusing: entry)
            } catch {
                show(error)
            }
        }
    }

    /// Stops a launched server that isn't listening yet.
    func kill(_ entry: ManagedServer) {
        entry.stoppedByUser = true
        let pid = entry.pid
        Task {
            do {
                try await controller.stop([pid]) { _ in }
                forget(entry)
            } catch {
                entry.stoppedByUser = false
                show(error)
            }
        }
    }

    func managedServer(id: UUID) -> ManagedServer? {
        managed.first { $0.id == id }
    }

    func forget(_ entry: ManagedServer) {
        managed.removeAll { $0 === entry }
    }

    func dismissNotice() {
        notice = nil
    }

    // MARK: - Internals

    private func stopJob(_ job: JobResolver.Job, rowPID: Int32) async throws {
        try await controller.stop(job.pids) { phase in
            await MainActor.run {
                self.activity[rowPID] = phase == .terminating ? .stopping : .forceStopping
            }
        }
    }

    private func launch(_ spec: LaunchSpec, ports: [Int], name: String, framework: Framework?, reusing existing: ManagedServer?) async throws -> ManagedServer {
        let logFile = try LogFiles.newFile()
        let pid = try await controller.launch(spec, logFile: logFile)

        let entry: ManagedServer
        if let existing {
            entry = existing
            entry.pid = pid
            entry.state = .starting
            entry.stoppedByUser = false
            entry.logs.appendMarker("Restarted · \(Date.now.formatted(date: .omitted, time: .standard))")
        } else {
            entry = ManagedServer(pid: pid, spec: spec, expectedPorts: ports, displayName: name, framework: framework)
            entry.logs.appendMarker("$ \(spec.command)")
            managed.append(entry)
        }
        let tailer = LogTailer(url: logFile)
        entry.tailer = tailer
        follow(entry, pid: pid, tailer: tailer)
        return entry
    }

    /// Pumps log output into the session until the process exits, then records the exit code.
    private func follow(_ entry: ManagedServer, pid: Int32, tailer: LogTailer) {
        let exit = ExitWatch()
        Task { exit.code = await controller.exitStatus(of: pid) }
        Task { [weak entry] in
            while let entry, entry.pid == pid, exit.code == nil {
                if let text = await tailer.read() { entry.logs.append(text) }
                try? await Task.sleep(for: .milliseconds(250))
            }
            while exit.code == nil { try? await Task.sleep(for: .milliseconds(100)) }
            guard let entry, entry.pid == pid, let code = exit.code else { return }
            while let text = await tailer.read() { entry.logs.append(text) }
            // Its output is in memory now; the file has served its purpose.
            try? FileManager.default.removeItem(at: tailer.url)
            if entry.stoppedByUser { return }
            entry.state = .exited(code: code)
            entry.logs.appendMarker(code == 0 ? "Exited" : "Exited with code \(code)")
        }
    }

    private func show(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        notice = Notice(message: message)
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { notice = nil }
        }
    }
}

extension ManagedServer {
    func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        let fields = expectedPorts.map(String.init) + [displayName.lowercased(), framework?.label.lowercased()].compactMap { $0 }
        return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
    }
}

@MainActor
private final class ExitWatch {
    var code: Int32?
}
