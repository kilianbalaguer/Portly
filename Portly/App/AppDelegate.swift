import AppKit
import Observation

/// Owns the app's long-lived objects. Starting them here (rather than from the popover's
/// content) means polling and the hotkey work before the popover has ever been opened.
@MainActor
@Observable
final class AppDelegate: NSObject, NSApplicationDelegate {
    @ObservationIgnored let settings = AppSettings()
    @ObservationIgnored let store = ServerStore()
    @ObservationIgnored let popover = PopoverState()
    @ObservationIgnored let hotKeys = HotKeyCenter()
    private(set) var hotKeyError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.showAll = settings.showAllByDefault
        store.openPollInterval = .seconds(settings.pollInterval)
        popover.onChange = { [weak self] open in self?.store.setPopoverOpen(open) }
        store.start()
        applyHotKey()
        #if DEBUG
        DebugSupport.handleLaunchArguments(self)
        #endif
    }

    /// Registers the hotkey from settings; returns a user-facing error if it couldn't be.
    @discardableResult
    func applyHotKey() -> String? {
        do {
            try hotKeys.register(settings.hotKey) { [weak self] in self?.popover.hotKeyPressed() }
            hotKeyError = nil
        } catch {
            hotKeyError = error.localizedDescription
        }
        return hotKeyError
    }
}
