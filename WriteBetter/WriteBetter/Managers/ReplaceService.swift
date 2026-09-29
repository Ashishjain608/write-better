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

    /// How long we wait for the target to become frontmost before giving up.
    private static let activationTimeout: TimeInterval = 1.0
    private static let activationPollStep: TimeInterval = 0.02
    /// How long the target needs to read the pasteboard before we put it back.
    private static let pasteboardRestoreDelay: TimeInterval = 1.0

    func rememberFrontmostApp() {
        let current = NSWorkspace.shared.frontmostApplication
        // Never record ourselves — that would make Replace paste into the panel.
        // And never keep an older app either: pasting into a stale target is worse
        // than falling back to the clipboard.
        if current?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            sourceApp = nil
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
    /// The paste is only posted once the target is confirmed frontmost; otherwise
    /// the text stays on the clipboard and the outcome says so.
    ///
    /// - Parameter closePanel: called *before* the source app is reactivated —
    ///   the panel must be gone before the paste lands.
    @discardableResult
    func replace(_ text: String, closePanel: @escaping () -> Void) -> Outcome {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let writtenCount = PasteboardSnapshot.writeTransient(text, to: pasteboard)

        guard canReplace, let target = sourceApp, !target.isTerminated else {
            closePanel()
            copyToClipboard(text)   // not a temporary borrow: the user will paste this
            return .copiedToClipboard
        }

        closePanel()
        guard target.activate(options: []), waitUntilFrontmost(target) else {
            copyToClipboard(text)   // drop the transient marker and the restore
            return .copiedToClipboard
        }

        SyntheticKeystroke.postCommand(.v)

        // Give the target time to read the pasteboard, then put the user's
        // clipboard back — but only if nobody has copied anything since.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteboardRestoreDelay) {
            snapshot.restore(to: pasteboard, ifChangeCountIs: writtenCount)
        }

        return .replaced(appName: target.localizedName ?? "the app")
    }

    /// Bounded spin (same pattern as `TextExtractor`) — the caller needs an honest answer.
    private func waitUntilFrontmost(_ target: NSRunningApplication) -> Bool {
        let deadline = Date().addingTimeInterval(Self.activationTimeout)
        while Date() < deadline {
            if target.isTerminated { return false }
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(Self.activationPollStep))
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
    }

    /// Plain copy, no app switching. Used by `↩`, `⇧↩` and the Copy button.
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
