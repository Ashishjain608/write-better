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
///   so `isTrusted` is refreshed by a 1 s poll while a UI that cares is visible
///   (until trust is seen) and whenever the app becomes active.
/// * Deep-linking to System Settings is offered alongside the prompt, because the
///   prompt itself is unreliable.
@MainActor
final class AccessibilityManager: ObservableObject {

    static let shared = AccessibilityManager()

    @Published private(set) var isTrusted: Bool

    private var pollTask: Task<Void, Never>?
    private var watchers = 0

    private static let pollInterval: Duration = .seconds(1)

    init() {
        // Non-prompting check. Safe at launch.
        isTrusted = AXIsProcessTrusted()
        // Coming back from System Settings re-activates us: re-read right away.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Cheap, non-prompting re-read.
    func refresh() {
        let current = AXIsProcessTrusted()
        if current != isTrusted { isTrusted = current }
    }

    /// Ref-counted so the Welcome window and the General settings tab can both poll
    /// without stepping on each other. Balanced by `endPolling()` from `onDisappear`;
    /// stops by itself once trust is granted.
    func beginPolling() {
        watchers += 1
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if self.isTrusted { break }
            }
            self?.pollTask = nil
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
    }

    /// The reliable path when the system prompt does not appear.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url {
            NSWorkspace.shared.open(url)
        }
    }

    /// A sandboxed build can never be trusted, so the Replace feature is hidden
    /// rather than shown broken (§9.3 rule 6).
    var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }
}
