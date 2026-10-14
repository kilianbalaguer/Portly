import Foundation

/// Polls for listeners and turns them into `DevServer`s. Runs off the main actor;
/// per-process facts that don't change over a process's life (argv, cwd, project, framework)
/// are cached by pid + start time so each poll stays cheap.
actor ServerMonitor {
    private struct StaticInfo {
        var arguments: [String]
        var executablePath: String?
        var workingDirectory: String?
        var project: ProjectInfo?
        var framework: Framework?
    }

    private struct CacheKey: Hashable {
        var pid: Int32
        var start: Date?
    }

    private let scanner: PortScanner
    private var cache: [CacheKey: StaticInfo] = [:]

    init(scanner: PortScanner = PortScanner()) {
        self.scanner = scanner
    }

    func scan() async throws -> [DevServer] {
        let listeners = try await scanner.listeners()
        let ownPID = getpid()

        var portsByPID: [Int32: Set<Int>] = [:]
        var commandByPID: [Int32: String] = [:]
        for listener in listeners where listener.pid != ownPID {
            portsByPID[listener.pid, default: []].insert(listener.port)
            commandByPID[listener.pid] = listener.command
        }

        var facts: [Int32: ProcessFacts] = [:]
        for pid in portsByPID.keys {
            if let f = ProcessInspector.facts(for: pid) { facts[pid] = f }
        }

        // libproc can't read every cwd; ask lsof in one batch for the ones it missed.
        let missingCWD = portsByPID.keys.filter { pid in
            cache[CacheKey(pid: pid, start: facts[pid]?.startTime)] == nil && facts[pid]?.workingDirectory == nil
        }
        let lsofCWDs = await scanner.workingDirectories(for: missingCWD)

        var liveKeys = Set<CacheKey>()
        var servers: [DevServer] = []
        for (pid, ports) in portsByPID {
            let fact = facts[pid]
            // A process that vanished between lsof and here is simply skipped.
            if fact == nil, !ProcessInspector.isAlive(pid) { continue }
            let command = commandByPID[pid] ?? "?"

            let key = CacheKey(pid: pid, start: fact?.startTime)
            liveKeys.insert(key)
            let info: StaticInfo
            if let cached = cache[key] {
                info = cached
            } else {
                info = await describe(pid: pid, command: command, facts: fact, fallbackCWD: lsofCWDs[pid])
                cache[key] = info
            }

            servers.append(DevServer(
                pid: pid,
                ports: ports.sorted(),
                command: command,
                arguments: info.arguments,
                executablePath: info.executablePath,
                workingDirectory: info.workingDirectory,
                project: info.project,
                framework: info.framework,
                isDevServer: DevFilter.isDevServer(command: command, executablePath: info.executablePath,
                                                   project: info.project, framework: info.framework),
                startTime: fact?.startTime,
                residentBytes: fact?.residentBytes.map(Self.roundToMiB),
                ancestors: Self.ancestors(of: pid),
                isInspectable: fact != nil
            ))
        }
        cache = cache.filter { liveKeys.contains($0.key) }
        return servers.sorted { ($0.primaryPort, $0.pid) < ($1.primaryPort, $1.pid) }
    }

    private func describe(pid: Int32, command: String, facts: ProcessFacts?, fallbackCWD: String?) async -> StaticInfo {
        var arguments = ProcessInspector.arguments(for: pid) ?? []
        if arguments.isEmpty, let line = await scanner.commandLine(for: pid) {
            arguments = [line]
        }
        let cwd = facts?.workingDirectory ?? fallbackCWD
        var project = cwd.flatMap { ProjectDetector.project(containing: $0) }
        if project == nil {
            // Servers launched by a process manager often run from `/`; try the script's folder instead.
            project = arguments.dropFirst()
                .first { $0.hasPrefix("/") && !$0.hasPrefix("/usr/") && !$0.hasPrefix("/opt/homebrew/") }
                .flatMap { ProjectDetector.project(containing: ($0 as NSString).deletingLastPathComponent) }
        }
        let framework = FrameworkDetector.detect(arguments: arguments.isEmpty ? [command] : arguments,
                                                 projectPath: project?.path)
        return StaticInfo(arguments: arguments, executablePath: facts?.executablePath,
                          workingDirectory: cwd, project: project, framework: framework)
    }

    static func ancestors(of pid: Int32) -> [Int32] {
        var chain: [Int32] = []
        var current = pid
        while chain.count < 32, let parent = ProcessInspector.parentPID(of: current), parent > 1 {
            chain.append(parent)
            current = parent
        }
        return chain
    }

    private static func roundToMiB(_ bytes: UInt64) -> UInt64 {
        let mib: UInt64 = 1 << 20
        return (bytes + mib / 2) / mib * mib
    }
}
