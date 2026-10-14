import Foundation

/// A process with one or more listening TCP ports, enriched with project information.
struct DevServer: Identifiable, Sendable, Equatable {
    var pid: Int32
    /// Listening ports, ascending. Never empty.
    var ports: [Int]
    /// Process name as reported by lsof.
    var command: String
    var arguments: [String]
    var executablePath: String?
    var workingDirectory: String?
    var project: ProjectInfo?
    var framework: Framework?
    var isDevServer: Bool
    var startTime: Date?
    /// Resident memory, rounded to the nearest MiB so small fluctuations don't cause UI updates.
    var residentBytes: UInt64?
    /// Parent, grandparent, … up to (not including) launchd.
    var ancestors: [Int32]
    /// False when the kernel refused to describe the process (usually another user's process).
    var isInspectable: Bool

    var id: Int32 { pid }
    var primaryPort: Int { ports[0] }
    var url: URL { URL(string: "http://localhost:\(primaryPort)")! }
    var displayName: String { project?.name ?? command }
    var commandLine: String { arguments.isEmpty ? command : ShellQuoting.join(arguments) }

    /// Case-insensitive match against port, project, framework and process name.
    func matches(_ query: String) -> Bool {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return true }
        let fields = ports.map(String.init) + [project?.name, framework?.label, command].compactMap { $0?.lowercased() }
        return terms.allSatisfy { term in fields.contains { $0.contains(term) } }
    }
}
