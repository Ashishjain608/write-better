import AppKit
import Combine
import SwiftUI

@main
struct WriteBetterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var router = SettingsRouter.shared

    var body: some Scene {
        // A real `NSMenu` — the HIG-correct, keyboard-navigable, VoiceOver-correct
        // option. `.window` style loses all three (§11.2 pitfall 9).
        MenuBarExtra {
            MenuBarMenu(settings: settings, delegate: appDelegate)
        } label: {
            // Derived, not stored: the "needs setup" rung has to react the moment a
            // key is saved anywhere in the app.
            MenuBarIconView(state: appDelegate.isWorking
                            ? .working
                            : (settings.configuredProviders.isEmpty ? .needsSetup : .ready))
        }
        .menuBarExtraStyle(.menu)

        // A real Settings scene. The previous build used `WindowGroup { EmptyView() }`,
        // which renders an actual empty window (its saved frame is still in the
        // user's prefs) — that scene is gone.
        Settings {
            SettingsView(settings: settings, router: router)
        }
    }
}

// MARK: - Menu bar menu (§7.3)

struct MenuBarMenu: View {
    @ObservedObject var settings: SettingsStore
    let delegate: AppDelegate

    @ObservedObject private var accessibility = AccessibilityManager.shared

    var body: some View {
        // Disabled header row — current provider + model, or the setup nudge.
        Text(headerText)
            .font(Theme.Font.caption)

        Divider()

        if settings.configuredProviders.isEmpty {
            Button {
                delegate.presentWelcome()
            } label: {
                Label("Set up WriteBetter…", systemImage: "sparkles")
            }
        } else {
            Button {
                delegate.improveFromClipboard()
            } label: {
                Label("Improve Clipboard Text", systemImage: "sparkles")
            }
            .keyboardShortcut(.space, modifiers: [.command, .shift])

            if accessibility.isTrusted {
                Button {
                    delegate.improveFromSelection()
                } label: {
                    Label("Improve Selection", systemImage: "text.cursor")
                }
            }
        }

        Divider()

        Menu("Provider") {
            ForEach(AIProvider.allCases) { provider in
                providerSection(provider)
            }
        }

        Divider()

        Button {
            SettingsRouter.shared.open()
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut(",", modifiers: .command)

        Button {
            delegate.showKeyboardShortcuts()
        } label: {
            Label("Keyboard Shortcuts…", systemImage: "keyboard")
        }

        Divider()

        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit WriteBetter", systemImage: "power")
        }
        .keyboardShortcut("q", modifiers: .command)
    }

    private var headerText: String {
        guard !settings.configuredProviders.isEmpty else { return "No provider configured" }
        let provider = settings.selectedProvider
        let modelID = settings.modelID(for: provider)
        let modelName = provider.models.first { $0.id == modelID }?.name ?? modelID
        return "\(provider.displayName) · \(modelName)"
    }

    /// Configured providers list their models; unconfigured ones offer only
    /// "Add API key…", which deep-links Settings to that row.
    @ViewBuilder
    private func providerSection(_ provider: AIProvider) -> some View {
        if settings.configuredProviders.contains(provider) {
            Menu {
                ForEach(provider.models) { model in
                    Button {
                        settings.setModelID(model.id, for: provider)
                        settings.selectedProvider = provider
                    } label: {
                        Text(settings.modelID(for: provider) == model.id && settings.selectedProvider == provider
                             ? "✓ \(model.name)"
                             : "   \(model.name)")
                    }
                }
            } label: {
                Text(settings.selectedProvider == provider
                     ? "✓ \(provider.displayName)"
                     : "   \(provider.displayName)")
            }
        } else {
            Button {
                SettingsRouter.shared.open(provider: provider)
            } label: {
                Text("   \(provider.displayName) — Add API key…")
            }
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {

    /// Drives the menu-bar icon's pulsing dot (M20).
    @Published private(set) var isWorking = false

    private let extractor = TextExtractor()
    private let replaceService = ReplaceService()
    private let hotkeyManager = HotkeyManager()

    private var panel: PopupWindowController?
    private var welcome: WelcomeWindowController?
    private var stateObservation: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // `WriteBetter.app --self-check` runs the no-network request/SSE/prompt
        // assertions and exits with the result. Keeps the suite runnable from CI
        // without a test target.
        if CommandLine.arguments.contains("--self-check") {
            exit(WriteBetterSelfCheck.runAll() ? 0 : 1)
        }
        #endif

        // Menu-bar app: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)

        AppearancePreference.current.apply()
        syncLaunchAtLogin()
        refreshMenuBarState()

        hotkeyManager.registerHotkey { [weak self] in
            self?.improveFromHotkey()
        }

        // Never prompts — a plain, non-prompting read (§9.3 rule 1).
        AccessibilityManager.shared.refresh()

        if WelcomeWindowController.shouldPresent {
            presentWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregister()
        stateObservation?.cancel()
    }

    // MARK: Entry points

    /// The global ⇧⌘Space path.
    func improveFromHotkey() {
        showPanel(preferSelection: SettingsStore.shared.autoCaptureSelection)
    }

    func improveFromClipboard() {
        showPanel(preferSelection: false)
    }

    func improveFromSelection() {
        showPanel(preferSelection: true)
    }

    func showKeyboardShortcuts() {
        SettingsRouter.shared.open(tab: .about)
    }

    func presentWelcome() {
        welcome?.close()
        let controller = WelcomeWindowController(settings: .shared) { [weak self] in
            self?.welcome = nil
            self?.refreshMenuBarState()
        }
        welcome = controller
        controller.showWindow(nil)
    }

    // MARK: Panel

    private func showPanel(preferSelection: Bool) {
        // Captured BEFORE anything of ours is shown or activated, or a later ⌘V
        // lands in our own panel (§11.2 pitfall 3).
        replaceService.rememberFrontmostApp()

        let capture = extractor.capture(preferSelection: preferSelection)

        panel?.close()
        panel = nil

        let controller = ImprovementController(settings: .shared, replaceService: replaceService)
        let windowController = PopupWindowController(controller: controller,
                                                     extractor: extractor,
                                                     at: NSEvent.mouseLocation)
        panel = windowController
        windowController.showWindow(nil)
        controller.begin(capture: capture)

        observe(controller)
    }

    /// Drives the menu-bar "working" dot from the panel's phase. Stops the moment
    /// the panel goes away, so a stream cancelled by closing the panel can't leave
    /// the dot pulsing forever.
    private func observe(_ controller: ImprovementController) {
        stateObservation?.cancel()
        stateObservation = Task { [weak self, weak controller] in
            while !Task.isCancelled {
                guard let self, let controller,
                      self.panel?.window?.isVisible == true else {
                    self?.isWorking = false
                    return
                }
                let working = controller.phase.isBusy
                if self.isWorking != working { self.isWorking = working }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func refreshMenuBarState() {
        isWorking = false
    }

    // MARK: Launch at login

    /// Keeps the persisted flag and the system's actual registration in step —
    /// the user can turn the login item off in System Settings behind our back.
    private func syncLaunchAtLogin() {
        let store = SettingsStore.shared
        let registered = LaunchAtLoginManager.isRegistered
        if store.launchAtLogin != registered {
            if store.launchAtLogin {
                do {
                    try LaunchAtLoginManager.apply(true)
                } catch {
                    store.launchAtLogin = false
                }
            } else {
                store.launchAtLogin = registered
            }
        }
    }
}
