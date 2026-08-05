import AppKit
import ApplicationServices

/// Three-tier text capture, in descending order of fidelity:
///
/// 1. **Accessibility** — `kAXSelectedTextAttribute` on the frontmost app's focused
///    element. Instant, non-destructive, no pasteboard involvement.
/// 2. **Synthetic ⌘C** — for apps that expose no AX selection (Electron, some web
///    views). The pasteboard is saved and restored around it.
/// 3. **Existing clipboard** — always available, needs no permission.
///
/// Tiers 1 and 2 are gated behind `AXIsProcessTrusted()` **and** the user's
/// "Use the current selection" preference. The app is fully usable on tier 3 alone,
/// which is why nothing here ever prompts for Accessibility (§9.3).
@MainActor
final class TextExtractor {

    /// Where the text we are about to improve came from — surfaced in the UI so the
    /// user is never guessing.
    enum Source {
        case selection
        case copiedSelection
        case clipboard

        var label: String {
            switch self {
            case .selection:       return "from your selection"
            case .copiedSelection: return "from your selection"
            case .clipboard:       return "from your clipboard"
            }
        }
    }

    struct Capture {
        let text: String
        let source: Source
        /// True when the input was longer than `maxCharacters` and was cut (§9.4).
        let truncated: Bool
    }

    /// §9.4 — anything past this is dropped, with a visible warning.
    static let maxCharacters = 20_000

    /// How long we wait for a synthetic ⌘C to land before giving up.
    private static let copyTimeout: TimeInterval = 0.20

    /// - Parameter preferSelection: the user's `autoCaptureSelection` preference.
    ///   When false we never touch the frontmost app at all.
    func capture(preferSelection: Bool) -> Capture? {
        if preferSelection, AXIsProcessTrusted() {
            if let text = selectedTextViaAccessibility() {
                return make(text, .selection)
            }
            if let text = selectedTextViaSyntheticCopy() {
                return make(text, .copiedSelection)
            }
        }
        if let text = clipboardText() {
            return make(text, .clipboard)
        }
        return nil
    }

    /// Tier 3 on its own — used by the empty-input state's "Try again".
    func clipboardText() -> String? {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: - Tier 1: Accessibility

    private func selectedTextViaAccessibility() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focusedRef) == .success,
              let focused = focusedRef,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }

        let element = unsafeBitCast(focused, to: AXUIElement.self)

        var selectedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextAttribute as CFString,
                                            &selectedRef) == .success,
              let text = selectedRef as? String,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        return text
    }

    // MARK: - Tier 2: synthetic ⌘C with save/restore

    private func selectedTextViaSyntheticCopy() -> String? {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        let changeCountBefore = pasteboard.changeCount

        SyntheticKeystroke.postCommand(.c)

        // Bounded spin — the panel must still feel instant.
        let deadline = Date().addingTimeInterval(Self.copyTimeout)
        while Date() < deadline, pasteboard.changeCount == changeCountBefore {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        guard pasteboard.changeCount != changeCountBefore,
              let copied = pasteboard.string(forType: .string),
              !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        // Put the user's clipboard back — we borrowed it, we return it.
        if let previous, previous != copied {
            pasteboard.clearContents()
            pasteboard.setString(previous, forType: .string)
        }

        return copied
    }

    // MARK: - Helpers

    private func make(_ raw: String, _ source: Source) -> Capture {
        if raw.count > Self.maxCharacters {
            let cut = String(raw.prefix(Self.maxCharacters))
            return Capture(text: cut, source: source, truncated: true)
        }
        return Capture(text: raw, source: source, truncated: false)
    }
}
