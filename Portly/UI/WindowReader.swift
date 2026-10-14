import AppKit
import SwiftUI

/// Reports the hosting window and whether it's open. MenuBarExtra's panel becomes key when it
/// opens and resigns key as it closes, which is the most reliable open/closed signal it offers.
struct WindowReader: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    var onOpenChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        view.onOpenChange = onOpenChange
        return view
    }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onWindow = onWindow
        view.onOpenChange = onOpenChange
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        var onOpenChange: ((Bool) -> Void)?
        // Only touched on the main thread; nonisolated so deinit can clean up.
        nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            guard let window else { return }
            onWindow?(window)
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpenChange?(true) }
            })
            observers.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpenChange?(false) }
            })
            if window.isKeyWindow || window.isVisible { onOpenChange?(true) }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

/// Handles list navigation keys while the popover is key: ↑/↓ move the selection, Return opens,
/// Escape goes back or closes. A local monitor sees these before the search field consumes them.
@MainActor
final class PopoverKeyMonitor {
    enum Key { case up, down, enter, escape }

    weak var window: NSWindow?
    var handler: ((Key) -> Bool)?
    private var monitor: Any?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let windowID = event.window.map(ObjectIdentifier.init)
            let consumed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, hasModifiers: !flags.isEmpty, windowID: windowID) ?? false
            }
            return consumed ? nil : event
        }
    }

    private func handle(keyCode: UInt16, hasModifiers: Bool, windowID: ObjectIdentifier?) -> Bool {
        guard let window, windowID == ObjectIdentifier(window), !hasModifiers else { return false }
        let key: Key? = switch Int(keyCode) {
        case 126: .up
        case 125: .down
        case 36, 76: .enter
        case 53: .escape
        default: nil
        }
        guard let key, let handler else { return false }
        return handler(key)
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
