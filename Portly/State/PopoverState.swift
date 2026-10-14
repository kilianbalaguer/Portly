import Observation

/// Whether the popover is showing, and requests that the popover UI reacts to.
@MainActor
@Observable
final class PopoverState {
    private(set) var isOpen = false
    /// Bumped each time the hotkey opens the popover, so the view can reset to a focused search.
    private(set) var hotKeyOpenCount = 0

    @ObservationIgnored var onChange: ((Bool) -> Void)?

    func setOpen(_ open: Bool) {
        guard open != isOpen else { return }
        isOpen = open
        onChange?(open)
    }

    func hotKeyPressed() {
        if !isOpen { hotKeyOpenCount += 1 }
        MenuBarBridge.toggle()
    }
}
