import AppKit
import Combine
import SwiftUI

// MARK: - Commands

/// Everything the panel's keyboard map can ask for (§7.1). The window owns the key
/// monitor; the SwiftUI view subscribes to the resulting commands.
enum PanelCommand: Equatable {
    case escape
    case copyAndClose
    case copyStay
    case replace
    case regenerate
    case focusPrompt
    case clearPrompt
    case quickAction(Int)
    case nextProvider
    case previousProvider
    case openSettings
    case toggleHelp
}

/// The bridge between the AppKit key monitor and the SwiftUI panel.
@MainActor
final class PanelKeyRouter: ObservableObject {
    let commands = PassthroughSubject<PanelCommand, Never>()

    /// True once ⌘ has been held for >400 ms — reveals index badges on the chips
    /// and swaps the footer hints to their ⌘ variants (Superhuman's pattern).
    @Published var isCommandHeld = false

    func send(_ command: PanelCommand) {
        commands.send(command)
    }
}

// MARK: - The panel

/// `canBecomeKey` must be true for a borderless panel, otherwise `close()` silently
/// fails after an `orderFront` (§11.2 pitfall 2) and no key events ever arrive.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Controller

@MainActor
final class PopupWindowController: NSWindowController, NSWindowDelegate {

    private let controller: ImprovementController
    private let router = PanelKeyRouter()
    private let extractor: TextExtractor
    private let anchorPoint: NSPoint

    private var keyMonitor: Any?
    private var flagsMonitor: Any?
    private var clickMonitor: Any?
    private var commandHoldWorkItem: DispatchWorkItem?

    /// Where the panel's top-left corner should stay as its height changes.
    private var topLeftAnchor: NSPoint = .zero
    private var isProgrammaticMove = false
    private var didFinishInitialPlacement = false

    /// Grammarly's lesson: a floating surface must remember where the user put it.
    /// Keyed by screen so a laptop/external-display move doesn't inherit a bad spot.
    private static var draggedOrigins: [String: NSPoint] = [:]

    private static let panelWidth: CGFloat = 560
    private static let screenMargin: CGFloat = 12

    init(controller: ImprovementController,
         extractor: TextExtractor,
         at point: NSPoint) {
        self.controller = controller
        self.extractor = extractor
        self.anchorPoint = point

        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        super.init(window: panel)
        configure(panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Setup

    private func configure(_ panel: KeyablePanel) {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        // AppKit draws the e3 shadow *outside* the window frame. A SwiftUI shadow
        // here would be clipped to the window bounds (§11.2 pitfall 1).
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.delegate = self
        panel.isReleasedWhenClosed = false

        controller.onClose = { [weak self] in self?.close() }
        controller.onOpenSettings = { provider in
            SettingsRouter.shared.open(provider: provider)
        }
        controller.onAnnounce = { message in
            NSAccessibility.post(element: NSApp as Any,
                                 notification: .announcementRequested,
                                 userInfo: [.announcement: message,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }

        let root = ImprovementView(controller: controller,
                                   router: router,
                                   extractor: extractor,
                                   settings: .shared)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize]
        panel.contentViewController = hosting

        // Without this the visual-effect material paints square corners underneath
        // the SwiftUI rounded clip (§11.2 pitfall 8).
        if let contentView = panel.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = Theme.Radius.panel
            contentView.layer?.cornerCurve = .continuous
            contentView.layer?.masksToBounds = true
        }

        place(panel)
        installMonitors()
    }

    // MARK: Placement

    private func place(_ panel: NSPanel) {
        let size = panel.frame.size
        let screen = Self.screen(containing: anchorPoint)

        var origin = NSPoint(x: anchorPoint.x + 12,
                             y: anchorPoint.y - size.height - 12)

        if let screen, let remembered = Self.draggedOrigins[Self.identifier(for: screen)] {
            origin = remembered
        }

        origin = Self.clamp(origin: origin, size: size, on: screen)
        isProgrammaticMove = true
        panel.setFrameOrigin(origin)
        isProgrammaticMove = false
        topLeftAnchor = NSPoint(x: origin.x, y: origin.y + size.height)
        didFinishInitialPlacement = true
    }

    private static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private static func identifier(for screen: NSScreen) -> String {
        let frame = screen.frame
        return "\(Int(frame.origin.x))x\(Int(frame.origin.y))x\(Int(frame.width))x\(Int(frame.height))"
    }

    private static func clamp(origin: NSPoint, size: NSSize, on screen: NSScreen?) -> NSPoint {
        guard let visible = screen?.visibleFrame else { return origin }
        var result = origin
        let margin = screenMargin
        result.x = min(max(result.x, visible.minX + margin), visible.maxX - size.width - margin)
        result.y = min(max(result.y, visible.minY + margin), visible.maxY - size.height - margin)
        return result
    }

    // MARK: Monitors

    private func installMonitors() {
        // Scoped to *this* window. The previous build's monitor fired for Settings
        // and every other window in the app (§11.2 pitfall 4).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            return self.handle(event) ? nil : event
        }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            self.handleFlags(event)
            return event
        }

        // Global monitors never see our own app's clicks, so opening Settings from
        // the panel does not dismiss it.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let window = self.window else { return }
            guard !window.frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
    }

    private func removeMonitors() {
        for monitor in [keyMonitor, flagsMonitor, clickMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        flagsMonitor = nil
        clickMonitor = nil
        commandHoldWorkItem?.cancel()
        commandHoldWorkItem = nil
    }

    // MARK: Key handling (§7.1 keyboard map)

    /// - Returns: true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let isEditingText = window?.firstResponder is NSTextView

        switch event.keyCode {
        case 53:                                    // esc
            router.send(.escape)
            return true
        case 36, 76:                                // return / enter
            if command {
                router.send(.replace)
                return true
            }
            // A focused field owns Return so `onSubmit` can run the custom prompt.
            if isEditingText { return false }
            router.send(shift ? .copyStay : .copyAndClose)
            return true
        case 51 where command && isEditingText:     // ⌘⌫
            router.send(.clearPrompt)
            return true
        default:
            break
        }

        guard let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty else {
            return false
        }

        if command {
            switch characters {
            case "r": router.send(.regenerate); return true
            case "k": router.send(.focusPrompt); return true
            case ",": router.send(.openSettings); return true
            case "]": router.send(.nextProvider); return true
            case "[": router.send(.previousProvider); return true
            case "c": return false                  // let the selectable Text copy (§11.2 pitfall 5)
            default: break
            }
            // ⌘1…⌘9 — generated from QuickAction.allCases, never hardcoded.
            if let digit = Int(characters), (1...9).contains(digit) {
                router.send(.quickAction(digit - 1))
                return true
            }
            return false
        }

        if characters == "?" || (shift && characters == "/") {
            guard !isEditingText else { return false }
            router.send(.toggleHelp)
            return true
        }

        return false
    }

    /// ⌘ held for >400 ms reveals the chip index badges.
    private func handleFlags(_ event: NSEvent) {
        let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        commandHoldWorkItem?.cancel()

        guard held else {
            router.isCommandHeld = false
            return
        }
        let work = DispatchWorkItem { [weak self] in self?.router.isCommandHeld = true }
        commandHoldWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    // MARK: NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        guard didFinishInitialPlacement, let window else { return }
        // Keep the top edge pinned as the intrinsic height changes while streaming,
        // so the panel grows downward instead of jumping.
        let size = window.frame.size
        var origin = NSPoint(x: topLeftAnchor.x, y: topLeftAnchor.y - size.height)
        origin = Self.clamp(origin: origin, size: size, on: Self.screen(containing: origin) ?? window.screen)
        guard origin != window.frame.origin else { return }
        isProgrammaticMove = true
        window.setFrameOrigin(origin)
        isProgrammaticMove = false
        window.invalidateShadow()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isProgrammaticMove, didFinishInitialPlacement, let window else { return }
        let frame = window.frame
        topLeftAnchor = NSPoint(x: frame.minX, y: frame.maxY)
        if let screen = window.screen {
            Self.draggedOrigins[Self.identifier(for: screen)] = frame.origin
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.level = .floating
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another *app* dismisses the panel via the global monitor, so the
        // only way to reach this is one of our own windows (Settings / Welcome)
        // taking key. Drop out of `.floating` so the panel doesn't sit on top of it —
        // §8.1 wants the panel to stay open *behind* Settings, not in front.
        window?.level = .normal
    }

    func windowWillClose(_ notification: Notification) {
        // Guaranteed cleanup — the previous build leaked its click monitor whenever
        // the window closed by any route other than `close()`.
        removeMonitors()
        controller.teardown()
    }

    // MARK: Show / close

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        // `makeKey` is required or a later programmatic `close()` does nothing.
        window?.makeKeyAndOrderFront(nil)
        window?.invalidateShadow()
    }

    override func close() {
        removeMonitors()
        super.close()
    }

    deinit {
        // `deinit` may run off the main actor; the monitors were already removed in
        // `windowWillClose`, which AppKit always delivers.
    }
}
