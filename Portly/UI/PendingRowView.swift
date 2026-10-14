import SwiftUI

/// A server Portly launched that isn't listening: still starting, or exited.
struct PendingRowView: View {
    let entry: ManagedServer
    let isSelected: Bool
    let onLogs: () -> Void
    let onRestart: () -> Void
    let onStop: () -> Void
    let onDismiss: () -> Void

    @State private var hovering = false

    private var failed: Bool {
        if case .exited(let code) = entry.state { return code != 0 }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Group {
                    switch entry.state {
                    case .starting: Spinner(size: 10)
                    case .running: StatusDot(color: .secondary, pulsing: false)
                    case .exited: StatusDot(color: failed ? Theme.danger : .secondary, pulsing: false)
                    }
                }
                .frame(width: 16, height: 16)
                Text(entry.expectedPorts.first.map(String.init) ?? "–")
                    .font(Theme.portFont())
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 42, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.displayName).font(Theme.titleFont).lineLimit(1)
                    if let framework = entry.framework { Pill(text: framework.label, tint: .secondary) }
                }
                Text(status)
                    .font(Theme.metaFont)
                    .foregroundStyle(failed ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.displayName), \(status)")

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                IconButton(systemImage: "text.alignleft", label: "Show logs", tint: failed ? Theme.accent : .secondary, action: onLogs)
                switch entry.state {
                case .starting, .running:
                    IconButton(systemImage: "stop.circle", label: "Stop", tint: Theme.danger.opacity(0.85), action: onStop)
                case .exited:
                    IconButton(systemImage: "arrow.clockwise", label: "Start again", action: onRestart)
                    IconButton(systemImage: "xmark", label: "Dismiss", action: onDismiss)
                }
            }
            .opacity(hovering || isSelected || failed ? 1 : 0.0001)
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 48)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(isSelected ? Theme.accent.opacity(0.13) : failed ? Theme.danger.opacity(0.07) : hovering ? Theme.hoverFill : .clear)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private var status: String {
        switch entry.state {
        case .starting:
            return "Starting… · \(entry.spec.command)"
        case .running:
            return "Running, not listening on a port"
        case .exited(let code):
            let headline = code == 0 ? "Exited" : "Exited with code \(code)"
            if let last = entry.logs.lastMeaningfulLine { return "\(headline) · \(last)" }
            return headline
        }
    }
}
