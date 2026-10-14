import Darwin
import Foundation

/// Everything needed to start a server again: what to run, where, and which tool folders to
/// put on PATH so version-managed runtimes (nvm, asdf, …) resolve to the same binaries.
struct LaunchSpec: Sendable, Equatable {
    /// A shell-ready command line.
    var command: String
    var workingDirectory: String
    var pathHints: [String]

    /// Builds a command line from a process's argv. Tools like npm overwrite their argv with a
    /// title (`["npm run dev", "", ""]`); that title is a command line already and is used verbatim.
    static func commandLine(fromArguments arguments: [String]) -> String? {
        guard let first = arguments.first?.trimmingCharacters(in: .whitespaces), !first.isEmpty else { return nil }
        let rest = arguments.dropFirst()
        let isRewrittenTitle = rest.allSatisfy { $0.isEmpty } && first.contains(" ")
            && !FileManager.default.fileExists(atPath: first)
        if isRewrittenTitle { return first }
        return ShellQuoting.join(Array(arguments.filter { !$0.isEmpty }))
    }
}

/// The user's login shell and how to run a command through it.
enum LoginShell {
    static var path: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        if let shell = ProcessInfo.processInfo.environment["SHELL"], FileManager.default.isExecutableFile(atPath: shell) {
            return shell
        }
        return "/bin/zsh"
    }

    /// Arguments for `<shell> -l -c <script>`: load the login profile, then cd and exec the command.
    static func invocation(for spec: LaunchSpec, shell: String = path) -> (shell: String, arguments: [String]) {
        let name = (shell as NSString).lastPathComponent
        let cwd = ShellQuoting.quote(spec.workingDirectory)
        let hints = spec.pathHints.map(ShellQuoting.quote)
        let script: String
        if name == "fish" {
            let path = hints.isEmpty ? "" : "set -gx PATH \(hints.joined(separator: " ")) $PATH; "
            script = "\(path)cd \(cwd); and exec \(spec.command)"
        } else if ["zsh", "bash", "sh", "ksh", "dash"].contains(name) {
            let path = hints.isEmpty ? "" : "export PATH=\(hints.joined(separator: ":")):\"$PATH\"; "
            script = "\(path)cd \(cwd) && exec \(spec.command)"
        } else {
            // csh, nushell, …: their syntax differs, so fall back to zsh for the launch itself.
            return invocation(for: spec, shell: "/bin/zsh")
        }
        return (shell, ["-l", "-c", script])
    }
}
