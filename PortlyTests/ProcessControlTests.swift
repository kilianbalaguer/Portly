import XCTest
@testable import Portly

/// End-to-end: launch `npm run dev` through the login shell the way Restart does, find it,
/// resolve its job, capture its output, then stop the whole job.
final class ProcessControlTests: XCTestCase {
    func testLaunchCaptureAndStopNpmJob() async throws {
        let npmDirs = ["/usr/local/bin", "/opt/homebrew/bin"].filter { FileManager.default.fileExists(atPath: "\($0)/npm") }
        try XCTSkipIf(npmDirs.isEmpty, "npm isn't installed")

        let port = Int.random(in: 42000...42999)
        let project = FileManager.default.temporaryDirectory.appendingPathComponent("lh-npm-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: project) }
        try Data(#"{"name":"demo","scripts":{"dev":"node server.js"},"dependencies":{"express":"4"}}"#.utf8)
            .write(to: project.appendingPathComponent("package.json"))
        try Data("""
        require("http").createServer((q, s) => s.end("ok")).listen(\(port), () => console.log("ready on \(port)"));
        process.on("SIGTERM", () => { console.log("bye"); process.exit(0); });
        """.utf8).write(to: project.appendingPathComponent("server.js"))

        let controller = ProcessController()
        let logFile = try LogFiles.newFile()
        defer { try? FileManager.default.removeItem(at: logFile) }
        let spec = LaunchSpec(command: "npm run dev", workingDirectory: project.path, pathHints: npmDirs)
        let shellPID = try await controller.launch(spec, logFile: logFile)
        let exit = Task { await controller.exitStatus(of: shellPID) }

        // Detect it.
        let monitor = ServerMonitor()
        var found: DevServer?
        for _ in 0..<60 where found == nil {
            try await Task.sleep(for: .milliseconds(250))
            found = try await monitor.scan().first { $0.ports.contains(port) }
        }
        let server = try XCTUnwrap(found, "npm server not detected")
        XCTAssertEqual(server.project?.name, project.lastPathComponent)
        XCTAssertEqual(server.framework, .express)
        XCTAssertTrue(server.ancestors.contains(shellPID), "listener should descend from the launched process")

        // Job: node server.js → npm run dev (the login shell exec'd into npm).
        let job = JobResolver.job(for: server)
        XCTAssertEqual(job.pids.first, server.pid)
        XCTAssertEqual(job.root, shellPID)
        let relaunch = try XCTUnwrap(JobResolver.launchSpec(for: server, job: job))
        XCTAssertEqual(relaunch.command, "npm run dev")
        XCTAssertEqual(URL(fileURLWithPath: relaunch.workingDirectory).resolvingSymlinksInPath(), project.resolvingSymlinksInPath())

        // Logs.
        let tailer = LogTailer(url: logFile)
        var output = ""
        for _ in 0..<20 where !output.contains("ready on") {
            output += await tailer.read() ?? ""
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(output.contains("ready on \(port)"), "log was: \(output)")

        // Stop.
        try await controller.stop(job.pids) { _ in }
        let code = await exit.value
        XCTAssertNotEqual(code, -1)
        let stillListening = try await PortScanner().listeners().contains { $0.port == port }
        XCTAssertFalse(stillListening)
    }

    func testStopEscalatesToSIGKILLWhenSIGTERMIsIgnored() async throws {
        let controller = ProcessController()
        let logFile = try LogFiles.newFile()
        defer { try? FileManager.default.removeItem(at: logFile) }
        let spec = LaunchSpec(command: #"sh -c 'trap "" TERM; echo started; while :; do sleep 0.1; done'"#,
                              workingDirectory: NSTemporaryDirectory(), pathHints: [])
        let pid = try await controller.launch(spec, logFile: logFile)
        let exit = Task { await controller.exitStatus(of: pid) }
        try await Task.sleep(for: .milliseconds(800))   // let the trap install

        let phases = PhaseRecorder()
        let started = ContinuousClock.now
        try await controller.stop([pid]) { await phases.record($0) }
        let elapsed = ContinuousClock.now - started

        let recorded = await phases.phases
        XCTAssertEqual(recorded, [.terminating, .forceKilling])
        XCTAssertGreaterThanOrEqual(elapsed, ProcessController.gracePeriod)
        let code = await exit.value
        XCTAssertEqual(code, 128 + SIGKILL)
    }

    func testFailingCommandReportsExitCodeAndOutput() async throws {
        let controller = ProcessController()
        let logFile = try LogFiles.newFile()
        defer { try? FileManager.default.removeItem(at: logFile) }
        let spec = LaunchSpec(command: #"sh -c 'echo "Error: Cannot find module server.js" >&2; exit 3'"#,
                              workingDirectory: NSTemporaryDirectory(), pathHints: [])
        let pid = try await controller.launch(spec, logFile: logFile)
        let code = await controller.exitStatus(of: pid)
        XCTAssertEqual(code, 3)
        let output = await LogTailer(url: logFile).read() ?? ""
        XCTAssertTrue(output.contains("Cannot find module"), output)
    }

    func testLaunchInMissingFolderFails() async {
        let spec = LaunchSpec(command: "true", workingDirectory: "/nonexistent-\(UUID())", pathHints: [])
        do {
            _ = try await ProcessController().launch(spec, logFile: URL(fileURLWithPath: "/dev/null"))
            XCTFail("expected an error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("no longer exists"))
        }
    }

    func testCommandLineFromRewrittenTitle() {
        XCTAssertEqual(LaunchSpec.commandLine(fromArguments: ["npm run dev", "", "", ""]), "npm run dev")
        XCTAssertEqual(LaunchSpec.commandLine(fromArguments: ["node", "my server.js"]), "node 'my server.js'")
        XCTAssertNil(LaunchSpec.commandLine(fromArguments: []))
    }

    func testLoginShellScript() {
        let spec = LaunchSpec(command: "npm run dev", workingDirectory: "/Users/me/my app", pathHints: ["/Users/me/.nvm/versions/node/v20/bin"])
        let zsh = LoginShell.invocation(for: spec, shell: "/bin/zsh")
        XCTAssertEqual(zsh.arguments, ["-l", "-c", "export PATH=/Users/me/.nvm/versions/node/v20/bin:\"$PATH\"; cd '/Users/me/my app' && exec npm run dev"])
        let fish = LoginShell.invocation(for: spec, shell: "/opt/homebrew/bin/fish")
        XCTAssertEqual(fish.arguments.last, "set -gx PATH /Users/me/.nvm/versions/node/v20/bin $PATH; cd '/Users/me/my app'; and exec npm run dev")
        XCTAssertEqual(LoginShell.invocation(for: spec, shell: "/bin/tcsh").shell, "/bin/zsh")
    }

    func testLogTextCleanup() {
        XCTAssertEqual(LogText.lines(from: "\u{1B}[32m✓\u{1B}[39m ready\r\nnext\n"), ["✓ ready", "next"])
        XCTAssertEqual(LogText.lines(from: "10%\r50%\r100%\n"), ["100%"])
        XCTAssertEqual(LogText.stripANSI("\u{1B}]8;;http://x\u{1B}\\link\u{1B}]8;;\u{1B}\\"), "link")
    }
}

private actor PhaseRecorder {
    var phases: [ProcessController.StopPhase] = []
    func record(_ phase: ProcessController.StopPhase) { phases.append(phase) }
}
