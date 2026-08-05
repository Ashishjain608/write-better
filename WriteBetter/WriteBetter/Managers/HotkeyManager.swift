import Carbon.HIToolbox
import Foundation

/// The one global hotkey: ⇧⌘Space.
///
/// Carbon's `RegisterEventHotKey` is still the only API that gives a background app
/// a system-wide shortcut without Accessibility trust, which is why it survives here:
/// the app must work before the user has granted anything (§9.3).
final class HotkeyManager {

    /// Rendered as keycaps wherever the shortcut is displayed.
    static let displayKeys = ["⇧", "⌘", "␣"]
    static let displayString = "⇧⌘Space"

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var callback: (() -> Void)?

    private(set) var isRegistered = false

    /// - Returns: false when the shortcut is already claimed by another app.
    @discardableResult
    func registerHotkey(callback: @escaping () -> Void) -> Bool {
        guard !isRegistered else { return true }
        self.callback = callback

        let keyCode = UInt32(kVK_Space)
        let modifiers = UInt32(cmdKey | shiftKey)
        let hotKeyID = EventHotKeyID(signature: OSType(0x68746B31), id: 1)   // 'htk1'
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                // Escape the Carbon handler before touching AppKit, or the window
                // work lands inside a Carbon transaction and deadlocks.
                DispatchQueue.main.async { manager.callback?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard installStatus == noErr else { return false }

        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = registerStatus == noErr
        return isRegistered
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        isRegistered = false
    }

    deinit {
        unregister()
    }
}
