import Foundation

/// Finds TCP listeners on this machine.
struct PortScanner: Sendable {
    var runner: any CommandRunning = ProcessCommandRunner()

    /// Runs `lsof -iTCP -sTCP:LISTEN -P -n` (with `+c 0 -F pcn` for full, machine-readable output).
    func listeners() async throws -> [Listener] {
        let result = try await runner.run("/usr/sbin/lsof", ["-iTCP", "-sTCP:LISTEN", "-P", "-n", "+c", "0", "-F", "pcn"])
        // lsof exits 1 when nothing matches; that's an empty list, not a failure.
        guard result.status == 0 || (result.status == 1 && result.stdout.isEmpty) else {
            throw ScanError.lsofFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return LsofParser.parseListeners(result.stdout)
    }

    /// Fallback for when libproc can't read a working directory: `lsof -a -p <pids> -d cwd -Fn`.
    func workingDirectories(for pids: [Int32]) async -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let list = pids.map(String.init).joined(separator: ",")
        guard let result = try? await runner.run("/usr/sbin/lsof", ["-a", "-p", list, "-d", "cwd", "-F", "pn"]) else { return [:] }
        return LsofParser.parseWorkingDirectories(result.stdout)
    }

    /// Fallback for argv: `ps -o command= -p <pid>`.
    func commandLine(for pid: Int32) async -> String? {
        guard let result = try? await runner.run("/bin/ps", ["-o", "command=", "-p", String(pid)]), result.status == 0 else { return nil }
        let line = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
}

enum ScanError: LocalizedError {
    case lsofFailed(String)

    var errorDescription: String? {
        switch self {
        case .lsofFailed(let detail):
            detail.isEmpty ? "Couldn't list open ports." : "Couldn't list open ports: \(detail)"
        }
    }
}
