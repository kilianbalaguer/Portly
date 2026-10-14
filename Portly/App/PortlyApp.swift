import SwiftUI

@main
struct PortlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(delegate.store)
                .environment(delegate.popover)
                .environment(delegate.settings)
        } label: {
            Image(nsImage: MenuBarGlyph.image(count: delegate.store.devServerCount))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(delegate.settings)
                .environment(delegate)
        }
    }
}
