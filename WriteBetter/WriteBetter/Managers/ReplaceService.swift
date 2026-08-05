import AppKit
import ApplicationServices

/// Puts the improved text back where it came from.
///
/// The sequence matters (§11.2 pitfall 3). `NSApp.activate(ignoringOtherApps:)`
/// makes *us* frontmost, so a naive ⌘V would paste into our own panel. The source
/// app is therefore captured **before** the panel is ever shown, and the paste is
/// posted only after that app has been reactivated.
@MainActor
final class ReplaceService {

    /// What actually happened, so the UI can say so rather than leaving the user to guess.
    enum Outcome {
        /// Pasted straight back into the source app.
        case replaced(appName: String)
        /// Accessibility unavailable, or no source app — the text is on the clipboard.
        case copiedToClipboard
    }

    /// The app that was frontmost when the hotkey fired. Captured by `AppDelegate`
    /// before the panel appears.
    private(set) var sourceApp: NSRunningApplication?

    /// How long the reactivated app needs before it can receive a keystroke.
    private static let activationDelay: TimeInterval = 0.08
    /// How long the target needs to read the pasteboard before we put it back.
    private static let pasteboardRestoreDelay: TimeInterval = 0.30

    func rememberFrontmostApp() {
        let current = NSWorkspace.shared.frontmostApplication
        // Never record ourselves — that would make Replace paste into the panel.
        if current?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return
        }
        sourceApp = current
    }

    func forgetFrontmostApp() {
        sourceApp = nil
    }

    /// True when the Replace affordance can actually do something.
    var canReplace: Bool {
        AXIsProcessTrusted() && sourceApp != nil
    }

    /// Copies `text` to the pasteboard and, when possible, pastes it into the source app.
    ///
    /// - Parameter closePanel: called *before* the source app is reactivated —
    ///   the panel must be gone before the paste lands.
    @discardableResult
    func replace(_ text: String, closePanel: @escaping () -> Void) -> Outcome {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard canReplace, let target = sourceApp else {
            closePanel()
            return .copiedToClipboard
        }

        closePanel()
        target.activate(options: [])

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationDelay) {
            SyntheticKeystroke.postCommand(.v)

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteboardRestoreDelay) {
                // Restore whatever the user had before we borrowed the pasteboard.
                if let previousContents, previousContents != text {
                    pasteboard.clearContents()
                    pasteboard.setString(previousContents, forType: .string)
                }
            }
        }

        return .replaced(appName: target.localizedName ?? "the app")
    }

    /// Plain copy, no app switching. Used by `↩`, `⇧↩` and the Copy button.
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
