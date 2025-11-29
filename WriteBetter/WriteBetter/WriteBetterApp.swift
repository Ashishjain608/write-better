import SwiftUI

@main
struct WriteBetterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty scene since we're using a menu bar app with custom windows
        WindowGroup {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popupWindow: PopupWindowController?
    var hotkeyManager: HotkeyManager?
    var textExtractor: TextExtractor?
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Setup menu bar
        setupMenuBar()

        // Initialize managers
        textExtractor = TextExtractor()
        hotkeyManager = HotkeyManager()

        // Register hotkey
        hotkeyManager?.registerHotkey { [weak self] in
            self?.handleHotkeyPressed()
        }

        // Check accessibility permissions
        checkAccessibilityPermissions()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            // Use SF Symbol for the icon
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "WriteBetter")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit WriteBetter", action: #selector(quit), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView()
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 550, height: 500),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "WriteBetter Settings"
            settingsWindow?.contentView = NSHostingView(rootView: settingsView)
            settingsWindow?.center()
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func handleHotkeyPressed() {
        guard let selectedText = textExtractor?.getSelectedText() else {
            print("No text selected")
            return
        }

        // Get cursor position
        let cursorPosition = NSEvent.mouseLocation

        // Show popup window
        showPopup(with: selectedText, at: cursorPosition)
    }

    private func showPopup(with text: String, at position: NSPoint) {
        // Close existing popup if any
        popupWindow?.close()

        // Create and show new popup
        popupWindow = PopupWindowController(originalText: text, position: position)
        popupWindow?.showWindow(nil)
    }

    private func checkAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if !accessEnabled {
            print("Accessibility permissions not granted. Please enable in System Preferences.")
        }
    }
}
