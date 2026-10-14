import Carbon.HIToolbox
import Foundation

/// Registers one global hotkey with Carbon's `RegisterEventHotKey`, which works without the
/// Accessibility permission (unlike global NSEvent monitors).
@MainActor
final class HotKeyCenter {
    enum RegistrationError: LocalizedError {
        case alreadyTaken
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .alreadyTaken: "That shortcut is already used by another app."
            case .failed(let status): "The shortcut couldn't be registered (error \(status))."
            }
        }
    }

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPress: (() -> Void)?
    private static let signature: OSType = 0x5052544C  // 'PRTL'

    /// Replaces the current hotkey. Pass nil to remove it.
    func register(_ combo: KeyCombo?, onPress: @escaping () -> Void) throws {
        unregister()
        self.onPress = onPress
        guard let combo else { return }
        installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            throw status == eventHotKeyExistsErr ? RegistrationError.alreadyTaken : RegistrationError.failed(status)
        }
        hotKeyRef = ref
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<HotKeyCenter>.fromOpaque(context).takeUnretainedValue().onPress?()
            }
            return noErr
        }, 1, &eventType, context, &handlerRef)
    }
}
