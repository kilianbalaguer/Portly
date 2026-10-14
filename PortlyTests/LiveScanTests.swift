import XCTest
@testable import Portly

/// Starts a real server in a temporary project and checks the full scan pipeline sees it.
final class LiveScanTests: XCTestCase {
    func testDetectsRealPythonServer() async throws {
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("lh-test-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("[project]\nname = \"demo\"\ndependencies = [\"flask\"]\n".utf8).write(to: project.appendingPathComponent("pyproject.toml"))
        defer { try? FileManager.default.removeItem(at: project) }

        let port = Int.random(in: 41000...41999)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1"]
        process.currentDirectoryURL = project
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer { process.terminate() }

        let monitor = ServerMonitor()
        var found: DevServer?
        for _ in 0..<40 where found == nil {
            try await Task.sleep(for: .milliseconds(250))
            found = try await monitor.scan().first { $0.ports.contains(port) }
        }
        let server = try XCTUnwrap(found, "server on \(port) not detected")
        XCTAssertEqual(server.project?.name, project.lastPathComponent)
        XCTAssertEqual(server.framework, .flask)
        XCTAssertTrue(server.isDevServer)
        XCTAssertTrue(server.arguments.contains("http.server"))
        XCTAssertNotNil(server.residentBytes)
        XCTAssertNotNil(server.startTime)
    }
}
