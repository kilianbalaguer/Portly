import Foundation
import Observation

/// A server Portly launched (via Restart), so it owns its output and knows its exit status.
@MainActor
@Observable
final class ManagedServer: Identifiable {
    enum State: Equatable {
        case starting
        case running
        case exited(code: Int32)
    }

    let id = UUID()
    var pid: Int32
    var spec: LaunchSpec
    /// Ports the server listened on before the restart; used to place it in the list while starting.
    var expectedPorts: [Int]
    var displayName: String
    var framework: Framework?
    var state: State = .starting
    let logs = LogSession()

    @ObservationIgnored var tailer: LogTailer?
    @ObservationIgnored var stoppedByUser = false

    init(pid: Int32, spec: LaunchSpec, expectedPorts: [Int], displayName: String, framework: Framework?) {
        self.pid = pid
        self.spec = spec
        self.expectedPorts = expectedPorts
        self.displayName = displayName
        self.framework = framework
    }

    /// True for the launched process itself and anything it spawned.
    func owns(_ server: DevServer) -> Bool {
        server.pid == pid || server.ancestors.contains(pid)
    }
}
