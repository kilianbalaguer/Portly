import SwiftUI

/// One running server: port, project, framework, memory, uptime, pid. Actions appear on hover
/// or when the row is selected with the keyboard.
struct ServerRowView: View {
    let server: DevServer
    let managed: ManagedServer?
    let isSelected: Bool
    let activity: RowActivity?
    let actions: RowActions

    @State private var hovering = false
    @State private var confirmingRestart = false
    @State private var copied = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsActions: Bool { (hovering || isSelected) && activity == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                leading
                info
                Spacer(minLength: 4)
                trailing
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 48)

            if confirmingRestart {
                RestartConfirmation(server: server, onCancel: { setConfirming(false) }, onConfirm: {
                    setConfirming(false)
                    actions.restart()
                })
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { actions.open() }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open in browser", actions.open)
        .accessibilityAction(named: "Copy URL", copyURL)
        .accessibilityAction(named: "Show logs", actions.logs)
        .accessibilityAction(named: "Restart") { requestRestart() }
        .accessibilityAction(named: "Stop", actions.kill)
    }

    // MARK: Pieces

    private var leading: some View {
        HStack(spacing: 4) {
            Group {
                if activity != nil || managed?.state == .starting {
                    Spinner(color: activity == .forceStopping ? Theme.warning : Theme.accent, size: 10)
                        .frame(width: 16, height: 16)
                } else {
                    StatusDot(color: server.isDevServer ? Theme.accent : .secondary, pulsing: server.isDevServer)
                }
            }
            Text(verbatim: String(server.primaryPort))
                .font(Theme.portFont())
                .foregroundStyle(server.isDevServer ? .primary : .secondary)
                .frame(minWidth: 42, alignment: .leading)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(server.displayName)
                    .font(Theme.titleFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(1)
                if let framework = server.framework {
                    Pill(text: framework.label, tint: Theme.accent)
                        .fixedSize()
                }
                if server.ports.count > 1 {
                    Text(verbatim: "+\(server.ports.dropFirst().map(String.init).joined(separator: " +"))")
                        .font(Theme.metaFont)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            meta
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var meta: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Group {
                if let activity {
                    Text(activity.label).foregroundStyle(activity == .forceStopping ? Theme.warning : Theme.accent)
                } else {
                    Text(metaText(now: context.date)).foregroundStyle(.secondary)
                }
            }
            .font(Theme.metaFont)
            .lineLimit(1)
        }
    }

    private func metaText(now: Date) -> String {
        var parts = [server.command]
        if let bytes = server.residentBytes { parts.append(Format.memory(bytes)) }
        if let start = server.startTime { parts.append("up " + Format.uptime(since: start, now: now)) }
        parts.append("pid \(server.pid)")
        if !server.isInspectable { parts.append("limited info") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trailing: some View {
        if showsActions {
            HStack(spacing: 0) {
                IconButton(systemImage: "safari", label: "Open in browser", size: 22, action: actions.open)
                IconButton(systemImage: copied ? "checkmark" : "link", label: copied ? "Copied" : "Copy URL",
                           tint: copied ? Theme.accent : .secondary, size: 22, action: copyURL)
                IconButton(systemImage: "text.alignleft", label: managed == nil ? "Logs" : "Show logs", size: 22, action: actions.logs)
                IconButton(systemImage: "arrow.clockwise", label: "Restart", size: 22, action: requestRestart)
                IconButton(systemImage: "stop.circle", label: "Stop (SIGTERM, then SIGKILL after 3 s)", tint: Theme.danger.opacity(0.85), size: 22, action: actions.kill)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
        } else if managed != nil, activity == nil {
            Image(systemName: "text.alignleft")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent.opacity(0.7))
                .help("Started by \(AppInfo.name): logs are captured")
                .accessibilityLabel("Logs captured")
        }
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
            .fill(isSelected ? Theme.accent.opacity(0.13) : hovering ? Theme.hoverFill : .clear)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                    .strokeBorder(isSelected ? Theme.accent.opacity(0.28) : .clear, lineWidth: 0.75)
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open in Browser", action: actions.open)
        Button("Copy URL", action: copyURL)
        Button("Show Logs", action: actions.logs)
        Divider()
        Button("Restart…", action: requestRestart)
        Button("Stop", action: actions.kill)
    }

    private var accessibilitySummary: String {
        var parts = ["Port \(server.primaryPort)", server.displayName]
        if let framework = server.framework { parts.append(framework.label) }
        if let bytes = server.residentBytes { parts.append(Format.memory(bytes)) }
        if let start = server.startTime { parts.append("running for " + Format.spokenUptime(since: start)) }
        parts.append("process \(server.command), pid \(server.pid)")
        if let activity { parts.append(activity.label) }
        return parts.joined(separator: ", ")
    }

    // MARK: Behaviour

    private func copyURL() {
        actions.copy()
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }

    /// Servers Portly launched restart right away; others get the caveat first.
    private func requestRestart() {
        if managed != nil { actions.restart() } else { setConfirming(true) }
    }

    private func setConfirming(_ value: Bool) {
        withAnimation(.localhost(reduceMotion: reduceMotion)) { confirmingRestart = value }
    }
}

struct RowActions {
    var open: () -> Void
    var copy: () -> Void
    var logs: () -> Void
    var restart: () -> Void
    var kill: () -> Void
}

/// Shown before restarting a server Portly didn't start: what will run, where, and the caveat.
private struct RestartConfirmation: View {
    let server: DevServer
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(server.commandLine)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                if let cwd = server.workingDirectory {
                    Text("in \(Format.path(cwd))")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.fieldFill))

            RestartCaveat()

            HStack(spacing: 6) {
                Spacer()
                CapsuleButton(title: "Cancel", tint: .secondary, action: onCancel)
                CapsuleButton(title: "Restart", systemImage: "arrow.clockwise", prominent: true, action: onConfirm)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm restart")
    }
}
