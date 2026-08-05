import AppKit
import CoreGraphics

/// Posts ⌘-key events into the *system* event stream so they land in whichever app
/// is frontmost — used for the tier-2 capture (⌘C) and for replace-in-place (⌘V).
///
/// Both require Accessibility trust; callers must check `AXIsProcessTrusted()`
/// first, because without it `CGEvent.post` is silently dropped.
enum SyntheticKeystroke {

    /// Virtual key codes (ANSI layout). These are physical-key constants, so they
    /// are correct on non-QWERTY layouts too.
    enum Key: CGKeyCode {
        case c = 8
        case v = 9
    }

    /// Posts a ⌘+key down/up pair to the HID event tap.
    static func postCommand(_ key: Key) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Stop our own ⌘ from leaking into the synthesised event's flags.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let down = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
