import XCTest
@testable import Portly

final class ParsingTests: XCTestCase {
    func testParsesLsofFieldOutput() {
        let output = """
        p470
        cControlCenter
        f10
        n*:7000
        f11
        n[::]:7000
        p9001
        cnext-server (v14.2.3)
        f22
        n127.0.0.1:3000
        f23
        n[::1]:9229
        """
        let listeners = LsofParser.parseListeners(output)
        XCTAssertEqual(listeners, [
            Listener(pid: 470, port: 7000, command: "ControlCenter"),
            Listener(pid: 9001, port: 3000, command: "next-server (v14.2.3)"),
            Listener(pid: 9001, port: 9229, command: "next-server (v14.2.3)"),
        ])
    }

    func testIgnoresMalformedAddresses() {
        XCTAssertNil(LsofParser.port(fromAddress: "*:*"))
        XCTAssertNil(LsofParser.port(fromAddress: "127.0.0.1:3000->127.0.0.1:5000"))
        XCTAssertNil(LsofParser.port(fromAddress: "localhost:99999"))
        XCTAssertEqual(LsofParser.port(fromAddress: "[fe80::1%lo0]:5173"), 5173)
    }

    func testParsesWorkingDirectories() {
        let dirs = LsofParser.parseWorkingDirectories("p12\nfcwd\nn/Users/me/my app\np13\nfcwd\nn/\n")
        XCTAssertEqual(dirs, [12: "/Users/me/my app", 13: "/"])
    }

    func testShellQuoting() {
        XCTAssertEqual(ShellQuoting.join(["npm", "run", "dev"]), "npm run dev")
        XCTAssertEqual(ShellQuoting.join(["node", "my server.js", "--name=it's"]), "node 'my server.js' '--name=it'\\''s'")
        XCTAssertEqual(ShellQuoting.quote(""), "''")
    }

    func testFrameworkFromCommandLine() {
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["node", "/p/node_modules/.bin/next", "dev"]), .nextjs)
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["next-server (v14.2.3)"]), .nextjs)
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["node", "/p/node_modules/.bin/vite", "--port", "5173"]), .vite)
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["python3", "manage.py", "runserver"]), .django)
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["puma 6.4.0 (tcp://localhost:3000) [app]"]), .rails)
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["php", "artisan", "serve"]), .laravel)
        XCTAssertEqual(FrameworkDetector.fromCommandLine(["php", "-S", "localhost:8000"]), .php)
        XCTAssertNil(FrameworkDetector.fromCommandLine(["node", "server.js"]))
    }

    func testFrameworkFromPackageJSON() {
        let json = #"{"dependencies":{"react":"18","next":"14"},"devDependencies":{"vite":"5"}}"#
        XCTAssertEqual(FrameworkDetector.fromPackageJSON(Data(json.utf8)), .nextjs)
        XCTAssertEqual(FrameworkDetector.fromPackageJSON(Data(#"{"dependencies":{"express":"4"}}"#.utf8)), .express)
        XCTAssertNil(FrameworkDetector.fromPackageJSON(Data("not json".utf8)))
    }

    func testDevFilter() {
        XCTAssertTrue(DevFilter.isDevServer(command: "node", executablePath: "/usr/local/bin/node", project: nil, framework: nil))
        XCTAssertTrue(DevFilter.isDevServer(command: "Python", executablePath: "/Library/Frameworks/Python.framework/Versions/3.12/Resources/Python.app/Contents/MacOS/Python", project: nil, framework: nil))
        XCTAssertFalse(DevFilter.isDevServer(command: "ControlCenter", executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter", project: nil, framework: nil))
        XCTAssertFalse(DevFilter.isDevServer(command: "Spotify", executablePath: "/Applications/Spotify.app/Contents/MacOS/Spotify", project: nil, framework: nil))
        XCTAssertFalse(DevFilter.isDevServer(command: "googled", executablePath: "/usr/local/bin/googled", project: nil, framework: nil))
        let project = ProjectInfo(name: "api", path: "/Users/me/api")
        XCTAssertTrue(DevFilter.isDevServer(command: "api", executablePath: "/Users/me/api/target/debug/api", project: project, framework: nil))
    }

    func testSearchMatching() {
        let server = DevServer(pid: 1, ports: [3000, 9229], command: "node", arguments: [], executablePath: nil,
                               workingDirectory: nil, project: ProjectInfo(name: "Storefront", path: "/x"),
                               framework: .nextjs, isDevServer: true, startTime: nil, residentBytes: nil,
                               ancestors: [], isInspectable: true)
        XCTAssertTrue(server.matches("300"))
        XCTAssertTrue(server.matches("9229"))
        XCTAssertTrue(server.matches("store next"))
        XCTAssertTrue(server.matches("NODE"))
        XCTAssertFalse(server.matches("vite"))
    }
}
