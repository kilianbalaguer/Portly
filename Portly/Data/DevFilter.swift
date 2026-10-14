import Foundation

/// Decides whether a listening process looks like a development server.
enum DevFilter {
    /// Process names (lower-cased, prefix match) that are almost always dev tooling.
    static let devProcessPrefixes = [
        "node", "bun", "deno", "python", "ruby", "php", "go", "vite", "next", "nuxt", "astro",
        "npm", "pnpm", "yarn", "npx", "tsx", "ts-node", "nodemon", "esbuild", "webpack",
        "uvicorn", "gunicorn", "flask", "django", "rails", "puma", "rackup", "bundle", "hugo", "jekyll",
        "cargo", "air", "dotnet", "beam.smp", "elixir", "mix", "java", "workerd", "wrangler", "storybook",
    ]

    /// Locations that hold system or app-bundled software rather than a user's project.
    static let systemPathPrefixes = ["/System/", "/usr/libexec/", "/usr/sbin/", "/sbin/", "/Library/Apple/"]

    static func isDevServer(command: String, executablePath: String?, project: ProjectInfo?, framework: Framework?) -> Bool {
        if framework != nil { return true }
        let name = command.lowercased()
        // "go" must be an exact match: "google…" helpers are not dev servers.
        if name == "go" { return true }
        if devProcessPrefixes.contains(where: { $0 != "go" && name.hasPrefix($0) }) {
            return !isInsideAppBundle(executablePath)
        }
        if let path = executablePath, systemPathPrefixes.contains(where: path.hasPrefix) || isInsideAppBundle(path) {
            return false
        }
        // Compiled servers (`go run`, `cargo run`, …) have arbitrary names but run from a project folder.
        return project != nil
    }

    private static func isInsideAppBundle(_ path: String?) -> Bool {
        guard let path else { return false }
        // Framework builds of Python run as `Python.framework/…/Python.app`; that's still a dev runtime.
        return path.contains(".app/Contents/") && !path.contains(".framework/")
    }
}
