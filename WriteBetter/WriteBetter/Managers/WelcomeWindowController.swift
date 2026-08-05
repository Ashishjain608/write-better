import AppKit
import SwiftUI

/// Hosts the first-run Welcome page (§9.1).
///
/// Presented once, only when nothing at all is configured, and never again
/// automatically — the menu-bar header row becomes the persistent nudge instead.
@MainActor
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {

    static let hasSeenWelcomeKey = "hasSeenWelcome"

    private var keyMonitor: Any?
    private var onDismiss: (() -> Void)?

    static var shouldPresent: Bool {
        guard !UserDefaults.standard.bool(forKey: hasSeenWelcomeKey) else { return false }
        return SettingsStore.shared.configuredProviders.isEmpty
    }

    init(settings: SettingsStore, onDismiss: @escaping () -> Void) {
        let window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        self.onDismiss = onDismiss

        window.isFloatingPanel = false
        window.level = .normal
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true                 // AppKit draws e3 outside the frame
        window.isMovableByWindowBackground = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.delegate = self

        let hosting = NSHostingController(rootView: WelcomeView(settings: settings) { [weak self] in
            self?.finish()
        })
        hosting.sizingOptions = [.preferredContentSize]
        window.contentViewController = hosting

        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = Theme.Radius.panel
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }

        window.center()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            guard event.keyCode == 53 else { return event }      // esc
            self.finish()
            return nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        // With LSUIElement the window opens behind everything unless we activate.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.invalidateShadow()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
        close()
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        UserDefaults.standard.set(true, forKey: Self.hasSeenWelcomeKey)
        onDismiss?()
        onDismiss = nil
    }
}
