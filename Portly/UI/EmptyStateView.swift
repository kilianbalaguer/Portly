import SwiftUI

struct EmptyStateView: View {
    enum Kind: Equatable {
        case scanning
        case noServers(hidden: Int)
        case noMatches(String)
    }

    let kind: Kind
    var onShowAll: () -> Void = {}

    var body: some View {
        VStack(spacing: 12) {
            switch kind {
            case .scanning:
                Spinner(size: 16)
                Text("Looking for servers…").font(.system(size: 12)).foregroundStyle(.secondary)
            case .noServers(let hidden):
                Beacon()
                VStack(spacing: 4) {
                    Text("No servers running").font(.system(size: 13, weight: .semibold))
                    Text("Start a dev server and it'll show up here.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                if hidden > 0 {
                    CapsuleButton(title: "Show \(hidden) other \(hidden == 1 ? "listener" : "listeners")", action: onShowAll)
                }
            case .noMatches(let query):
                Image(systemName: "magnifyingglass").font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary)
                Text("Nothing matches “\(query)”").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .accessibilityElement(children: .combine)
    }
}

/// Soft concentric rings around a quiet dot, slowly breathing.
private struct Beacon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        ZStack {
            ForEach(0..<3) { ring in
                Circle()
                    .strokeBorder(Theme.accent.opacity(0.22 - Double(ring) * 0.06), lineWidth: 1)
                    .frame(width: CGFloat(22 + ring * 18), height: CGFloat(22 + ring * 18))
                    .scaleEffect(breathe ? 1.06 : 0.96)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever().delay(Double(ring) * 0.25), value: breathe)
            }
            Circle()
                .fill(Theme.accent.opacity(0.55))
                .frame(width: 6, height: 6)
        }
        .frame(width: 64, height: 64)
        .onAppear { breathe = !reduceMotion }
        .accessibilityHidden(true)
    }
}
