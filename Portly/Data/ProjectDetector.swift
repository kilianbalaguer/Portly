import Foundation

struct ProjectInfo: Sendable, Equatable {
    var name: String
    var path: String
}

enum ProjectDetector {
    /// Files that mark the root of a project, checked from the working directory upward.
    static let markers = [
        "package.json", "pyproject.toml", "Gemfile", "Cargo.toml", "go.mod",
        "composer.json", "deno.json", "deno.jsonc", "mix.exs", "manage.py", ".git",
    ]

    /// Walks up from `directory` to the nearest folder containing a project marker.
    /// Never reports the home folder or `/` itself as a project.
    static func project(containing directory: String, fileManager: FileManager = .default) -> ProjectInfo? {
        let home = NSHomeDirectory()
        var url = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        while url.path != "/" && url.path != home {
            if markers.contains(where: { fileManager.fileExists(atPath: url.appendingPathComponent($0).path) }) {
                return ProjectInfo(name: url.lastPathComponent, path: url.path)
            }
            url.deleteLastPathComponent()
        }
        return nil
    }
}

/// A web framework or dev tool recognised from a process's command line or its project files.
enum Framework: String, Sendable, CaseIterable {
    case nextjs = "Next.js", nuxt = "Nuxt", remix = "Remix", astro = "Astro", svelteKit = "SvelteKit"
    case gatsby = "Gatsby", angular = "Angular", vite = "Vite", storybook = "Storybook", expo = "Expo"
    case webpack = "Webpack", createReactApp = "CRA", nest = "NestJS", express = "Express"
    case fastify = "Fastify", koa = "Koa", hono = "Hono", wrangler = "Wrangler"
    case django = "Django", fastAPI = "FastAPI", flask = "Flask", uvicorn = "Uvicorn", gunicorn = "Gunicorn"
    case rails = "Rails", sinatra = "Sinatra", laravel = "Laravel", php = "PHP"
    case phoenix = "Phoenix", hugo = "Hugo", jekyll = "Jekyll"

    var label: String { rawValue }
}

enum FrameworkDetector {
    /// Detects the framework, preferring the process's own command line (it says what is
    /// actually running) over the project's dependency list.
    static func detect(arguments: [String], projectPath: String?, fileManager: FileManager = .default) -> Framework? {
        if let match = fromCommandLine(arguments) {
            // uvicorn serves many ASGI apps; name FastAPI when the project depends on it.
            if match == .uvicorn, let projectPath, pythonDependencies(at: projectPath, fileManager: fileManager).contains("fastapi") {
                return .fastAPI
            }
            return match
        }
        guard let projectPath else { return nil }
        return fromProjectFiles(at: projectPath, fileManager: fileManager)
    }

    static func fromCommandLine(_ arguments: [String]) -> Framework? {
        let words = arguments.flatMap { $0.split(separator: " ") }.map { $0.lowercased() }
        let names = words.map { ($0 as NSString).lastPathComponent }
        let line = words.joined(separator: " ")

        func has(_ name: String) -> Bool { names.contains(name) }
        func contains(_ fragment: String) -> Bool { line.contains(fragment) }

        if names.contains(where: { $0.hasPrefix("next-server") }) || has("next") || contains("/next/dist/") { return .nextjs }
        if has("nuxt") || has("nuxi") || contains("/nuxt/") { return .nuxt }
        if has("remix") || contains("@remix-run/dev") { return .remix }
        if has("astro") { return .astro }
        if has("gatsby") { return .gatsby }
        if has("ng") && has("serve") || contains("@angular/cli") { return .angular }
        if has("storybook") || has("start-storybook") { return .storybook }
        if has("expo") { return .expo }
        if has("wrangler") || has("workerd") { return .wrangler }
        if has("vite") || contains("/vite/bin/") { return .vite }
        if has("webpack-dev-server") || (has("webpack") && has("serve")) { return .webpack }
        if has("react-scripts") { return .createReactApp }
        if has("nest") && has("start") { return .nest }
        if has("manage.py") && has("runserver") { return .django }
        if has("flask") { return .flask }
        if has("fastapi") { return .fastAPI }
        if has("uvicorn") { return .uvicorn }
        if has("gunicorn") { return .gunicorn }
        if has("rails") || names.contains(where: { $0.hasPrefix("puma") }) { return .rails }
        if has("artisan") && has("serve") { return .laravel }
        if names.contains(where: { $0 == "php" || $0.hasPrefix("php8") || $0.hasPrefix("php7") }) && has("-s") { return .php }
        if has("phx.server") { return .phoenix }
        if has("hugo") { return .hugo }
        if has("jekyll") { return .jekyll }
        return nil
    }

    static func fromProjectFiles(at path: String, fileManager: FileManager = .default) -> Framework? {
        let root = URL(fileURLWithPath: path, isDirectory: true)

        if let data = fileManager.contents(atPath: root.appendingPathComponent("package.json").path),
           let framework = fromPackageJSON(data) {
            return framework
        }
        let python = pythonDependencies(at: path, fileManager: fileManager)
        if python.contains("django") { return .django }
        if python.contains("fastapi") { return .fastAPI }
        if python.contains("flask") { return .flask }

        if let gemfile = fileManager.contents(atPath: root.appendingPathComponent("Gemfile").path) {
            let text = String(decoding: gemfile, as: UTF8.self)
            if text.contains("\"rails\"") || text.contains("'rails'") { return .rails }
            if text.contains("\"sinatra\"") || text.contains("'sinatra'") { return .sinatra }
        }
        if let composer = fileManager.contents(atPath: root.appendingPathComponent("composer.json").path),
           String(decoding: composer, as: UTF8.self).contains("laravel/framework") {
            return .laravel
        }
        return nil
    }

    /// Ordered from most to least specific: a Next.js app also depends on React, a SvelteKit app on Vite.
    static func fromPackageJSON(_ data: Data) -> Framework? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var deps = Set<String>()
        for key in ["dependencies", "devDependencies"] {
            if let section = json[key] as? [String: Any] { deps.formUnion(section.keys) }
        }
        let table: [(String, Framework)] = [
            ("next", .nextjs), ("nuxt", .nuxt), ("@remix-run/dev", .remix), ("@remix-run/node", .remix),
            ("astro", .astro), ("@sveltejs/kit", .svelteKit), ("gatsby", .gatsby), ("@angular/core", .angular),
            ("expo", .expo), ("@nestjs/core", .nest), ("vite", .vite), ("react-scripts", .createReactApp),
            ("wrangler", .wrangler), ("fastify", .fastify), ("hono", .hono), ("koa", .koa),
            ("express", .express), ("webpack-dev-server", .webpack),
        ]
        return table.first { deps.contains($0.0) }?.1
    }

    /// Lower-cased contents of pyproject.toml / requirements.txt, enough for substring checks.
    private static func pythonDependencies(at path: String, fileManager: FileManager) -> String {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        return ["pyproject.toml", "requirements.txt", "Pipfile"]
            .compactMap { fileManager.contents(atPath: root.appendingPathComponent($0).path) }
            .map { String(decoding: $0, as: UTF8.self).lowercased() }
            .joined(separator: "\n")
    }
}
