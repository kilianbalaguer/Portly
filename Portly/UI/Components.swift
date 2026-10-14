import SwiftUI

/// A borderless icon button with a soft hover circle, a tooltip and an accessibility label.
struct IconButton: View {
    let systemImage: String
    let label: String
    var tint: Color = .secondary
    var size: CGFloat = 24
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hovering ? AnyShapeStyle(tint == .secondary ? .primary : tint) : AnyShapeStyle(tint))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(SoftPressStyle(shape: Circle(), hovering: hovering))
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Hover / pressed fill shared by the custom buttons.
struct SoftPressStyle<S: Shape>: ButtonStyle {
    var shape: S
    var hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(shape.fill(configuration.isPressed ? Theme.pressedFill : hovering ? Theme.hoverFill : .clear))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A text button with a capsule hover fill, used for inline confirmations and empty states.
struct CapsuleButton: View {
    let title: String
    var systemImage: String?
    var prominent = false
    var tint: Color = Theme.accent
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)) }
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(tint))
            .background(Capsule().fill(prominent ? tint.opacity(hovering ? 1 : 0.88) : tint.opacity(hovering ? 0.2 : 0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A small rounded label, e.g. a framework name.
struct Pill: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(Theme.pillFont)
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.13)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }
}

/// A status dot with a slow, soft halo pulse. Static when Reduce Motion is on.
struct StatusDot: View {
    var color: Color = Theme.accent
    var pulsing = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        ZStack {
            if pulsing && !reduceMotion {
                Circle()
                    .fill(color.opacity(0.45))
                    .frame(width: 7, height: 7)
                    .scaleEffect(expanded ? 2.4 : 1)
                    .opacity(expanded ? 0 : 0.7)
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.6), radius: 3)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            guard pulsing && !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { expanded = true }
        }
        .accessibilityHidden(true)
    }
}

/// A small spinning arc, quieter than the stock progress indicator.
struct Spinner: View {
    var color: Color = Theme.accent
    var size: CGFloat = 12

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Circle()
            .trim(from: 0.15, to: 0.85)
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .opacity(reduceMotion ? 0.7 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { rotating = true }
            }
            .accessibilityHidden(true)
    }
}

/// A rounded search field with a leading glyph and an optional trailing hint (e.g. the hotkey).
struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var hint: String?
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused(focus)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if let hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hairline))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(focus.wrappedValue ? Theme.accent.opacity(0.55) : Theme.hairline, lineWidth: focus.wrappedValue ? 1 : 0.5)
        )
        .animation(.easeOut(duration: 0.15), value: focus.wrappedValue)
    }
}

/// A compact capsule toggle ("All") that reads as part of the header rather than a stock switch.
struct CapsuleToggle: View {
    let title: String
    @Binding var isOn: Bool
    var help: String

    @State private var hovering = false

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(isOn ? Theme.accent.opacity(0.16) : hovering ? Theme.hoverFill : .clear))
                .overlay(Capsule().strokeBorder(isOn ? Theme.accent.opacity(0.35) : Theme.hairline, lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
