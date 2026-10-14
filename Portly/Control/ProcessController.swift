import Darwin
import Foundation

enum ControlError: LocalizedError, Equatable {
    case permissionDenied(pid: Int32)
    case wouldNotExit(pid: Int32)
    case notRestartable(reason: String)
    case launchFailed(String)
    case portStillBusy(Int)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let pid):
            "Permission denied. Process \(pid) belongs to another user."
        case .wouldNotExit(let pid):
            "Process \(pid) didn't exit, even after a force quit."
        case .notRestartable(let reason):
            reason
        case .launchFailed(let detail):
            "Couldn't start the server: \(detail)"
        case .portStillBusy(let port):
            "Port \(port) is still in use by another process."
        }
    }
}

/// Stops and starts processes. Signals and waits happen off the main actor.
actor ProcessController {
    enum StopPhase: Sendable { case terminating, forceKilling }

    static let gracePeriod: Duration = .seconds(3)

    /// Sends SIGTERM to every pid, waits up to the grace period, then SIGKILLs survivors.
    /// `onPhase` reports progress so the UI can show "Stopping…" → "Force quitting…".
    func stop(_ pids: [Int32], onPhase: @Sendable (StopPhase) async -> Void) async throws {
        await onPhase(.terminating)
        try signal(pids, SIGTERM)
        if await waitForExit(pids, timeout: Self.gracePeriod) { return }

        await onPhase(.forceKilling)
        try signal(pids.filter(ProcessInspector.isAlive), SIGKILL)
        if await waitForExit(pids, timeout: .seconds(2)) { return }
        throw ControlError.wouldNotExit(pid: pids.first(where: ProcessInspector.isAlive) ?? pids[0])
    }

    private func signal(_ pids: [Int32], _ signal: Int32) throws {
        for pid in pids where kill(pid, signal) != 0 {
            if errno == ESRCH { continue }  // already gone
            if errno == EPERM { throw ControlError.permissionDenied(pid: pid) }
        }
    }

    private func waitForExit(_ pids: [Int32], timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !pids.contains(where: isRunning) { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return !pids.contains(where: isRunning)
    }

    /// Alive and not a zombie. Our own children linger as zombies until reaped, which happens
    /// asynchronously in `exitStatus(of:)`, so zombies count as exited.
    private func isRunning(_ pid: Int32) -> Bool {
        guard ProcessInspector.isAlive(pid) else { return false }
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return true }
        return bsd.pbi_status != UInt32(SZOMB)
    }

    /// Waits until nothing listens on `port` any more.
    func waitForPortToFree(_ port: Int, scanner: PortScanner, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let listeners = (try? await scanner.listeners()) ?? []
            if !listeners.contains(where: { $0.port == port }) { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    /// Starts `spec` through the user's login shell in a new session, with stdout and stderr
    /// appended to `logFile`. Returns the pid; the process outlives Portly if Portly quits.
    func launch(_ spec: LaunchSpec, logFile: URL) throws -> Int32 {
        guard FileManager.default.fileExists(atPath: spec.workingDirectory) else {
            throw ControlError.launchFailed("the folder \(spec.workingDirectory) no longer exists.")
        }
        let (shell, arguments) = LoginShell.invocation(for: spec)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, logFile.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
        posix_spawn_file_actions_adddup2(&fileActions, 1, 2)
        posix_spawn_file_actions_addchdir_np(&fileActions, spec.workingDirectory)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // New session: detached from Portly's process group and signals. CLOEXEC_DEFAULT keeps
        // our own file descriptors from leaking into the server.
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK))
        var defaultSignals = sigset_t()
        sigfillset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        var emptyMask = sigset_t()
        sigemptyset(&emptyMask)
        posix_spawnattr_setsigmask(&attributes, &emptyMask)

        let argv = ([shell] + arguments).map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        let envp = Self.baseEnvironment(shell: shell).map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { envp.forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, shell, &fileActions, &attributes, argv, envp)
        guard result == 0 else {
            throw ControlError.launchFailed(String(cString: strerror(result)))
        }
        return pid
    }

    /// Waits for a child we launched to exit, reaps it, and returns its exit code
    /// (128 + signal number when it was killed by a signal).
    nonisolated func exitStatus(of pid: Int32) async -> Int32 {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "Portly.exit.\(pid)")
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            let reap: @Sendable () -> Void = {
                var status: Int32 = 0
                guard waitpid(pid, &status, 0) == pid else {
                    continuation.resume(returning: -1)
                    return
                }
                let signal = status & 0x7f
                continuation.resume(returning: signal == 0 ? (status >> 8) & 0xff : 128 + signal)
            }
            source.setEventHandler {
                source.cancel()
                reap()
            }
            source.resume()
            // The child may have exited before the source was armed.
            queue.async {
                var info = siginfo_t()
                let peek = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
                if peek == 0 && info.si_pid == 0 { return }  // still running; the source will fire
                if !source.isCancelled {
                    source.cancel()
                    reap()
                }
            }
        }
    }

    /// The login shell rebuilds PATH and the rest from the user's profile; we only pass the basics.
    private static func baseEnvironment(shell: String) -> [String: String] {
        let current = ProcessInfo.processInfo.environment
        var env: [String: String] = [
            "HOME": NSHomeDirectory(),
            "SHELL": shell,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": current["LANG"] ?? "en_US.UTF-8",
        ]
        for key in ["USER", "LOGNAME", "TMPDIR"] {
            if let value = current[key] { env[key] = value }
        }
        return env
    }
}
