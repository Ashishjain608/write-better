import SwiftUI
import AppKit

class PopupWindowController: NSWindowController {
    private let originalText: String
    private let position: NSPoint

    init(originalText: String, position: NSPoint) {
        self.originalText = originalText
        self.position = position

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init(window: window)

        setupWindow(window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupWindow(_ window: NSPanel) {
        window.isFloatingPanel = true
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isMovableByWindowBackground = false

        // Create the SwiftUI view
        let contentView = ImprovementView(
            originalText: originalText,
            onClose: { [weak self] in
                self?.close()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)

        // Position the window near cursor
        positionWindow(window, near: position)

        // Close when clicking outside
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Monitor clicks outside the window
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let window = self?.window,
                  let eventWindow = event.window else {
                return event
            }

            if eventWindow != window {
                self?.close()
            }

            return event
        }
    }

    private func positionWindow(_ window: NSPanel, near point: NSPoint) {
        let windowSize = window.frame.size
        var origin = point

        // Adjust to position window slightly offset from cursor
        origin.x += 10
        origin.y -= windowSize.height + 10

        // Make sure window is on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame

            // Adjust horizontal position
            if origin.x + windowSize.width > screenFrame.maxX {
                origin.x = screenFrame.maxX - windowSize.width
            }
            if origin.x < screenFrame.minX {
                origin.x = screenFrame.minX
            }

            // Adjust vertical position
            if origin.y < screenFrame.minY {
                origin.y = point.y + 10 // Show above cursor instead
            }
            if origin.y + windowSize.height > screenFrame.maxY {
                origin.y = screenFrame.maxY - windowSize.height
            }
        }

        window.setFrameOrigin(origin)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }
}
