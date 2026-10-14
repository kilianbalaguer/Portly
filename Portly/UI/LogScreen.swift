import SwiftUI

/// Which logs the log screen shows.
enum LogTarget: Hashable {
    /// A server Portly launched; its output is captured.
    case managed(UUID)
    /// A server started elsewhere; its output can't be read.
    case external(pid: Int32)
}

struct LogScreen: View {
    @Environment(ServerStore.self) private var store
    @State var target: LogTarget
    let onBack: () -> Void

    @State private var filter = ""
    @State private var followsTail = true
    @State private var copied = false
    @FocusState private var filterFocused: Bool

    private var entry: ManagedServer? {
        if case .managed(let id) = target { return store.managedServer(id: id) }
        return nil
    }

    private var externalServer: DevServer? {
        if case .external(let pid) = target { return store.servers.first { $0.pid == pid } }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            content
        }
        .frame(height: 440)
        .onExitCommand(perform: onBack)
    }

    private var title: String {
        entry?.displayName ?? externalServer?.displayName ?? "Logs"
    }

    private var portText: String? {
        if let entry, let port = store.servers.first(where: entry.owns)?.primaryPort ?? entry.expectedPorts.first { return ":\(port)" }
        if let externalServer { return ":\(externalServer.primaryPort)" }
        return nil
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                IconButton(systemImage: "chevron.left", label: "Back to servers", action: onBack)
                    .keyboardShortcut("[", modifiers: .command)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(title).font(Theme.titleFont).lineLimit(1)
                        if let portText {
                            Text(portText).font(Theme.portFont(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                    if let entry { stateLine(entry) }
                }
                Spacer(minLength: 4)
                if let entry {
                    IconButton(systemImage: followsTail ? "arrow.down.to.line.compact" : "arrow.down.to.line",
                               label: followsTail ? "Following output" : "Follow output",
                               tint: followsTail ? Theme.accent : .secondary) {
                        followsTail.toggle()
                    }
                    IconButton(systemImage: copied ? "checkmark" : "doc.on.doc",
                               label: copied ? "Copied" : (filter.isEmpty ? "Copy all output" : "Copy matching lines"),
                               tint: copied ? Theme.accent : .secondary) {
                        copy(entry)
                    }
                    .disabled(entry.logs.lines.isEmpty)
                }
            }
            if entry != nil {
                SearchField(text: $filter, prompt: "Filter output", hint: nil, focus: $filterFocused)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func stateLine(_ entry: ManagedServer) -> some View {
        Group {
            switch entry.state {
            case .starting: Text("Starting…").foregroundStyle(Theme.accent)
            case .running: Text("Running · started by \(AppInfo.name)").foregroundStyle(.secondary)
            case .exited(let code): Text(code == 0 ? "Exited" : "Exited with code \(code)").foregroundStyle(code == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.danger))
            }
        }
        .font(.system(size: 10.5))
    }

    @ViewBuilder
    private var content: some View {
        if let entry {
            LogTextView(lines: entry.logs.lines, filter: filter, followsTail: $followsTail)
                .overlay {
                    if entry.state == .starting && entry.logs.lines.allSatisfy(\.isMarker) {
                        placeholder(icon: "text.alignleft", title: "Waiting for output…", message: nil)
                            .allowsHitTesting(false)
                    }
                }
        } else if let server = externalServer {
            unavailable(server)
        } else {
            placeholder(icon: "moon.zzz", title: "This server has stopped", message: "Its process is no longer running.")
        }
    }

    private func unavailable(_ server: DevServer) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "text.page.badge.magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent.opacity(0.8))
            VStack(spacing: 5) {
                Text("Logs aren't available yet").font(.system(size: 13, weight: .semibold))
                Text("This server was started outside \(AppInfo.name), so its output goes to the terminal that started it. Restart it here to capture logs from now on.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            if let activity = store.activity[server.pid] {
                HStack(spacing: 6) {
                    Spinner()
                    Text(activity.label).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .frame(height: 24)
            } else {
                CapsuleButton(title: "Restart in \(AppInfo.name) to capture logs", systemImage: "arrow.clockwise", prominent: true) {
                    store.restart(server) { entry in target = .managed(entry.id) }
                }
            }
            RestartCaveat()
                .padding(.horizontal, 28)
            Spacer()
        }
    }

    private func placeholder(icon: String, title: String, message: String?) -> some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: icon).font(.system(size: 24, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
            if let message { Text(message).font(.system(size: 11)).foregroundStyle(.tertiary) }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func copy(_ entry: ManagedServer) {
        let query = filter.lowercased()
        let text = entry.logs.lines
            .filter { query.isEmpty || $0.text.lowercased().contains(query) }
            .map(\.text)
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            copied = false
        }
    }
}

/// The honest caveat about restarting a server Portly didn't start.
struct RestartCaveat: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle").font(.system(size: 10))
            Text("Runs the same command in the same folder through your login shell. Environment variables set only in the original terminal session can't be recovered.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.tertiary)
    }
}

extension RowActivity {
    var label: String {
        switch self {
        case .stopping: "Stopping…"
        case .forceStopping: "Force quitting…"
        case .restarting: "Restarting…"
        }
    }
}
