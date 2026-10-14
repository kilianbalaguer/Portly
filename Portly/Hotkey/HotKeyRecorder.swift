import AppKit
import SwiftUI

/// Click, then press a shortcut. Escape cancels; Delete removes the shortcut.
struct HotKeyRecorder: View {
    @Binding var combo: KeyCombo?
    /// Called when recording starts/stops so the live hotkey can be paused meanwhile.
    var onRecordingChange: (Bool) -> Void = { _ in }

    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 6) {
                if recording {
                    Text("Type shortcut…").foregroundStyle(Theme.accent)
                } else if let combo {
                    Text(combo.displayString).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                } else {
                    Text("None").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12))
            .frame(minWidth: 96)
            .frame(height: 24)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(recording ? Theme.accent.opacity(0.12) : hovering ? Theme.pressedFill : Theme.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(recording ? Theme.accent.opacity(0.6) : Theme.hairline, lineWidth: recording ? 1 : 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(recording ? "Recording shortcut. Press the new shortcut, or Escape to cancel."
                                       : "Shortcut: \(combo?.accessibilityDescription ?? "none"). Click to change.")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = Int(event.keyCode)
            let newCombo = KeyCombo(event: event)
            let hasModifiers = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            MainActor.assumeIsolated {
                if keyCode == 53 && !hasModifiers {                  // Escape: cancel
                    stop()
                } else if (keyCode == 51 || keyCode == 117) && !hasModifiers {  // Delete: clear
                    combo = nil
                    stop()
                } else if let newCombo {
                    combo = newCombo
                    stop()
                } else {
                    NSSound.beep()                                    // needs ⌘, ⌃ or ⌥
                }
            }
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        onRecordingChange(false)
    }
}
