import Foundation

/// One process listening on one TCP port, as reported by lsof.
struct Listener: Sendable, Hashable {
    var pid: Int32
    var port: Int
    var command: String
}

enum LsofParser {
    /// Parses `lsof -F pcn` output. Each process starts with a `p<pid>` line, followed by a
    /// `c<command>` line and one `n<address>` line per open socket, e.g. `n*:3000` or `n[::1]:5173`.
    /// The field format is used instead of the column format because column output truncates
    /// command names and breaks on names containing spaces.
    static func parseListeners(_ output: String) -> [Listener] {
        var result: [Listener] = []
        var seen = Set<Listener>()
        var pid: Int32?
        var command = ""

        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = line.dropFirst()
            switch tag {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = String(value)
            case "n":
                guard let pid, let port = port(fromAddress: value) else { continue }
                let listener = Listener(pid: pid, port: port, command: command)
                if seen.insert(listener).inserted { result.append(listener) }
            default:
                continue
            }
        }
        return result
    }

    /// Parses `lsof -a -d cwd -F pn` output into a pid → directory map.
    static func parseWorkingDirectories(_ output: String) -> [Int32: String] {
        var result: [Int32: String] = [:]
        var pid: Int32?
        for line in output.split(whereSeparator: \.isNewline) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            if tag == "p" { pid = Int32(value) }
            else if tag == "n", let pid { result[pid] = value }
        }
        return result
    }

    /// Extracts the port from `*:3000`, `127.0.0.1:8080`, `[::1]:5173`.
    /// Returns nil for connected sockets (`a->b`) which never appear for LISTEN but are guarded anyway.
    static func port(fromAddress address: Substring) -> Int? {
        guard !address.contains("->"), let colon = address.lastIndex(of: ":") else { return nil }
        guard let port = Int(address[address.index(after: colon)...]), (1...65535).contains(port) else { return nil }
        return port
    }
}
