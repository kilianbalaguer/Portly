import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AppDelegate.self) private var app
    @State private var launchAtLogin = LaunchAtLogin()
    @State private var hotKeyError: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 18) {
            section("General") {
                row("Launch at login", detail: launchAtLogin.needsApproval ? "Waiting for approval in System Settings" : nil) {
                    Toggle("", isOn: Binding(get: { launchAtLogin.isEnabled }, set: { launchAtLogin.set($0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Launch at login")
                }
                if launchAtLogin.needsApproval {
                    CapsuleButton(title: "Open Login Items…", action: launchAtLogin.openSystemSettings)
                }
                if let error = launchAtLogin.error {
                    errorText(error)
                }
            }

            section("Shortcut") {
                row("Open \(AppInfo.name)", detail: "Opens the menu from anywhere with search focused") {
                    HotKeyRecorder(combo: Binding(get: { settings.hotKey }, set: { newValue in
                        settings.hotKey = newValue
                        hotKeyError = app.applyHotKey()
                    }), onRecordingChange: { recording in
                        if recording { app.hotKeys.unregister() } else { hotKeyError = app.applyHotKey() }
                    })
                }
                if settings.hotKey != .default {
                    Button("Reset to \(KeyCombo.default.displayString)") {
                        settings.hotKey = .default
                        hotKeyError = app.applyHotKey()
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
                if let hotKeyError {
                    errorText(hotKeyError)
                }
            }

            section("Servers") {
                row("Refresh every", detail: "While the menu is open. When it's closed, \(AppInfo.name) checks every 10 s to keep the count current.") {
                    Picker("", selection: $settings.pollInterval) {
                        ForEach(AppSettings.pollIntervalChoices, id: \.self) { seconds in
                            Text("\(Int(seconds)) s").tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                    .accessibilityLabel("Refresh interval")
                }
                row("Show all listeners by default", detail: "Include system and app processes, not just dev servers") {
                    Toggle("", isOn: $settings.showAllByDefault)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .accessibilityLabel("Show all listeners by default")
                }
            }

            Text("\(AppInfo.name) \(AppInfo.version)")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(20)
        .frame(width: 420)
        .tint(Theme.accent)
        .onAppear {
            launchAtLogin.refresh()
            hotKeyError = app.hotKeyError
            NSApp.activate(ignoringOtherApps: true)
        }
        .onChange(of: settings.pollInterval) { _, seconds in
            app.store.openPollInterval = .seconds(seconds)
        }
        .onChange(of: settings.showAllByDefault) { _, value in
            app.store.showAll = value
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 0.5))
        }
    }

    private func row<Control: View>(_ title: String, detail: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
    }

    private func errorText(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11))
            .foregroundStyle(Theme.danger)
    }
}
