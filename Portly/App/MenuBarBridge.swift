import AppKit

/// SwiftUI's MenuBarExtra has no API to open it programmatically, which the global hotkey needs.
/// The status item's button is a public `NSStatusBarButton` hosted in our app's status bar
/// window, so we find it there and click it.
@MainActor
enum MenuBarBridge {
    static var statusButton: NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("StatusBar") {
            if let button = findButton(in: window.contentView) { return button }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }

    /// Opens the popover, or closes it if it's already open.
    static func toggle() {
        NSApp.activate(ignoringOtherApps: true)
        statusButton?.performClick(nil)
    }
}
