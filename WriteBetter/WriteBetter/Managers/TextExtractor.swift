import Cocoa
import ApplicationServices

class TextExtractor {
    func getSelectedText() -> String? {
        // Save current clipboard
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Copy selected text to clipboard
        let source = CGEventSource(stateID: .hidSystemState)

        // Cmd+C to copy
        let cmdC = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 'C' key
        cmdC?.flags = .maskCommand
        cmdC?.post(tap: .cghidEventTap)

        let cmdCUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        cmdCUp?.flags = .maskCommand
        cmdCUp?.post(tap: .cghidEventTap)

        // Wait a bit for clipboard to update
        Thread.sleep(forTimeInterval: 0.1)

        // Get the selected text from clipboard
        let selectedText = pasteboard.string(forType: .string)

        // Restore previous clipboard contents
        if let previousContents = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previousContents, forType: .string)
        }

        return selectedText
    }
}
