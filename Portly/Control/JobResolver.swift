import Foundation

/// Works out which processes make up a running server "job". `npm run dev` typically runs as
/// npm → (sh -c) → node, and only the last one listens. Stopping just the listener would leave
/// npm behind (or let a watcher respawn it), so actions target the whole chain up to the
/// user's interactive shell or terminal.
enum JobResolver {
    struct Job: Sendable, Equatable {
        /// Listener first, outermost ancestor last.
        var pids: [Int32]
        var root: Int32 { pids.last! }
    }

    static let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "ksh", "tcsh", "csh", "nu"]
    static let boundaries: Set<String> = ["login", "tmux", "screen", "sshd", "launchd", "script", "mosh-server", "su", "sudo"]

    static func job(for server: DevServer) -> Job {
        var pids = [server.pid]
        guard let cwd = server.workingDirectory else { return Job(pids: pids) }

        for ancestor in server.ancestors {
            guard ancestor != getpid(), ProcessInspector.workingDirectory(for: ancestor) == cwd else { break }
            let name = ProcessInspector.executablePath(for: ancestor).map { ($0 as NSString).lastPathComponent } ?? ""
            if boundaries.contains(name) { break }
            if let path = ProcessInspector.executablePath(for: ancestor), path.contains(".app/Contents/"), !path.contains(".framework/") {
                break  // a terminal or editor
            }
            if shells.contains(name) {
                // `sh -c "next dev"` belongs to the job; an interactive shell is where we stop.
                let args = ProcessInspector.arguments(for: ancestor) ?? []
                guard args.contains("-c"), !(args.first ?? "").hasPrefix("-") else { break }
            }
            pids.append(ancestor)
        }
        return Job(pids: pids)
    }

    /// How to relaunch the job: the root's command line, run in the server's folder.
    static func launchSpec(for server: DevServer, job: Job) -> LaunchSpec? {
        guard let cwd = server.workingDirectory else { return nil }
        let rootArguments = job.root == server.pid ? server.arguments : (ProcessInspector.arguments(for: job.root) ?? [])
        guard var command = LaunchSpec.commandLine(fromArguments: rootArguments) else { return nil }

        // `sh -c "<script>"` → relaunch the script itself; our login shell provides the `sh`.
        if let name = rootArguments.first.map({ ($0 as NSString).lastPathComponent }), shells.contains(name),
           let flag = rootArguments.firstIndex(of: "-c"), flag + 1 < rootArguments.count {
            command = rootArguments[flag + 1]
        }

        // Put the folders of the binaries that were actually running first on PATH.
        var hints: [String] = []
        for pid in job.pids.reversed() {
            guard let exe = ProcessInspector.executablePath(for: pid) else { continue }
            let dir = (exe as NSString).deletingLastPathComponent
            let isSystem = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"].contains(dir) || dir.hasPrefix("/System/")
            if !isSystem, !hints.contains(dir), !dir.contains(".app/Contents/") { hints.append(dir) }
        }
        return LaunchSpec(command: command, workingDirectory: cwd, pathHints: hints)
    }
}
