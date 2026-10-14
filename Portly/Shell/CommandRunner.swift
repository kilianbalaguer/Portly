import Foundation

/// The result of running an external command to completion.
struct CommandResult: Sendable, Equatable {
    var status: Int32
    var stdout: String
    var stderr: String
}

enum CommandError: LocalizedError, Equatable {
    case launchFailed(String)
    case timedOut(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let detail): "Couldn't run command: \(detail)"
        case .timedOut(let command): "\(command) took too long and was stopped."
        }
    }
}

/// Runs short-lived commands (lsof, ps) and returns their output.
/// Abstracted so the scanner can be tested with canned output.
protocol CommandRunning: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> CommandResult
}

extension CommandRunning {
    func run(_ executable: String, _ arguments: [String]) async throws -> CommandResult {
        try await run(executable, arguments, timeout: .seconds(10))
    }
}

/// `CommandRunning` backed by `Foundation.Process`. All blocking I/O happens on a
/// dedicated dispatch queue, never on the main thread or the cooperative pool.
struct ProcessCommandRunner: CommandRunning {
    private static let ioQueue = DispatchQueue(label: "Portly.CommandRunner", attributes: .concurrent)

    func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            Self.ioQueue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
                process.standardInput = FileHandle.nullDevice
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.launchFailed(error.localizedDescription))
                    return
                }

                let timer = DispatchSource.makeTimerSource(queue: Self.ioQueue)
                let timedOut = LockedFlag()
                timer.schedule(deadline: .now() + timeout.timeInterval)
                timer.setEventHandler {
                    if process.isRunning {
                        timedOut.set()
                        process.terminate()
                    }
                }
                timer.resume()

                // Drain stderr concurrently so a chatty command can't deadlock on a full pipe.
                let errData = LockedData()
                let group = DispatchGroup()
                group.enter()
                Self.ioQueue.async {
                    errData.set(err.fileHandleForReading.readDataToEndOfFile())
                    group.leave()
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()
                timer.cancel()

                if timedOut.value {
                    continuation.resume(throwing: CommandError.timedOut(URL(fileURLWithPath: executable).lastPathComponent))
                    return
                }
                continuation.resume(returning: CommandResult(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errData.value, as: UTF8.self)
                ))
            }
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    var value: Data { lock.withLock { data } }
    func set(_ new: Data) { lock.withLock { data = new } }
}

extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
