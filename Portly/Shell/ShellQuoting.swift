import Foundation

enum ShellQuoting {
    /// Quotes a single argument for POSIX shells (sh, bash, zsh). Safe characters are left as-is
    /// so the command stays readable in the UI.
    static func quote(_ argument: String) -> String {
        if argument.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_")
        if argument.unicodeScalars.allSatisfy(safe.contains) { return argument }
        return "'" + argument.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func join(_ arguments: [String]) -> String {
        arguments.map(quote).joined(separator: " ")
    }
}
