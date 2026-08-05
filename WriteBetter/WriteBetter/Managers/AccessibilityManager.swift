import AppKit
import ApplicationServices
import Combine

/// Tracks whether the app holds Accessibility trust.
///
/// Three rules from §9.3 are baked in here so no caller can get them wrong:
///
/// * The prompting variant (`AXIsProcessTrustedWithOptions`) is **only** reachable
///   through `requestAccess()`, which is only ever called from a direct user click.
///   Nothing on the launch path can trigger it.
/// * `AXIsProcessTrusted()` returns a stale value after the user flips the switch,
///   so `isTrusted` is refreshed by a 1 s poll while a UI that cares is visible,
///   capped at 120 s.
/// * Deep-linking to System Settings is offered alongside the prompt, because the
///   prompt itself is unreliable.
@MainActor
final class AccessibilityManager: ObservableObject {

    static let shared = AccessibilityManager()

    @Published private(set) var isTrusted: Bool

    private var pollTask: Task<Void, Never>?
    private var watchers = 0

    private static let pollInterval: Duration = .seconds(1)
    private static let pollLimit = 120

    init() {
        // Non-prompting check. Safe at launch.
        isTrusted = AXIsProcessTrusted()
    }

    /// Cheap, non-prompting re-read.
    func refresh() {
        let current = AXIsProcessTrusted()
        if current != isTrusted { isTrusted = current }
    }

    /// Ref-counted so the Welcome window and the General settings tab can both poll
    /// without stepping on each other.
    func beginPolling() {
        watchers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            for _ in 0..<Self.pollLimit {
                try? await Task.sleep(for: Self.pollInterval)
                if Task.isCancelled { return }
                guard let self else { return }
                self.refresh()
                if self.isTrusted { return }
            }
        }
    }

    func endPolling() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    /// **Only** call this from a user's explicit click on "Enable…" / "Grant…".
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        beginPolling()
    }

    /// The reliable path when the system prompt does not appear.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
        beginPolling()
    }

    /// A sandboxed build can never be trusted, so the Replace feature is hidden
    /// rather than shown broken (§9.3 rule 6).
    var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
