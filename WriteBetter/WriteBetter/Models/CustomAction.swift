import Combine
import Foundation

/// A rewrite instruction the user saved. Runs exactly like the free-form prompt
/// (`controller.run(action: nil, customPrompt: instruction)`), but sits in the
/// panel as a chip after the built-in `QuickAction`s, on ⌘6–⌘9.
nonisolated struct CustomAction: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var instruction: String
    /// SF Symbol shown on the chip; nil shows the name alone.
    var icon: String?

    init(id: UUID = UUID(), name: String, instruction: String, icon: String? = nil) {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.icon = icon
    }

    // MARK: Limits

    /// Keeps four chips on one panel row.
    static let nameLimit = 24
    /// Roomy next to the built-in instructions (~300 characters each).
    static let instructionLimit = 500
    /// One slot per ⌘ digit left after the built-ins: 9 − 5 = 4 (⌘6–⌘9).
    static let maxCount = 9 - QuickAction.allCases.count

    /// The ⌘ digit for the saved action at `index`, or nil past the cap.
    static func shortcutDigit(at index: Int) -> Int? {
        guard index >= 0, index < maxCount else { return nil }
        return QuickAction.allCases.count + index + 1
    }

    /// "⌘6" or "⌘6–⌘9" for `count` saved actions; nil when there are none.
    static func shortcutRange(count: Int) -> String? {
        guard let first = shortcutDigit(at: 0), count > 0 else { return nil }
        guard count > 1, let last = shortcutDigit(at: min(count, maxCount) - 1) else { return "⌘\(first)" }
        return "⌘\(first)–⌘\(last)"
    }

    /// A name prefilled from a typed instruction: first line, cut at a word
    /// boundary to fit `nameLimit`, first letter capitalised.
    static func suggestedName(for instruction: String) -> String {
        let line = instruction
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        var name = line.trimmingCharacters(in: CharacterSet(charactersIn: " .,;:!?"))
        if name.count > nameLimit {
            let cut = String(name.prefix(nameLimit))
            name = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? cut
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// One-click examples offered by the empty Actions tab.
    static var starters: [CustomAction] {
        [
            CustomAction(name: "Translate to English",
                         instruction: "Translate the text into natural, fluent English. Keep the meaning, tone and formatting.",
                         icon: "globe"),
            CustomAction(name: "Make it a bullet list",
                         instruction: "Rewrite the text as a bulleted list, one point per line, each starting with \"- \". Keep every fact and drop filler words.",
                         icon: "list.bullet"),
            CustomAction(name: "Explain simply",
                         instruction: "Rewrite the text in plain, simple words that anyone can follow. Use short sentences and explain any jargon.",
                         icon: "lightbulb"),
        ]
    }

    /// Glyphs offered by the Settings editor. All ship with macOS 11+.
    static let iconChoices = [
        "globe", "list.bullet", "lightbulb", "text.quote", "envelope",
        "bubble.left", "star", "bolt", "hand.thumbsup", "doc.text",
    ]
}

/// The saved actions, in the user's order, persisted as JSON in UserDefaults.
/// Kept apart from `SettingsStore` so the list owns its own key and cap.
@MainActor
final class CustomActionStore: ObservableObject {
    static let shared = CustomActionStore()

    static let defaultsKey = "customActions"

    @Published private(set) var actions: [CustomAction]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.defaultsKey) ?? Data()
        // A corrupt or hand-edited value never crashes the app — it reads as empty.
        let decoded = (try? JSONDecoder().decode([CustomAction].self, from: data)) ?? []
        actions = Array(decoded.prefix(CustomAction.maxCount))
    }

    var isFull: Bool { actions.count >= CustomAction.maxCount }

    /// Appends (or inserts, for Undo). Returns false when every slot is taken.
    @discardableResult
    func add(_ action: CustomAction, at index: Int? = nil) -> Bool {
        guard !isFull else { return false }
        actions.insert(action, at: min(max(index ?? actions.count, 0), actions.count))
        save()
        return true
    }

    func update(_ action: CustomAction) {
        guard let index = actions.firstIndex(where: { $0.id == action.id }) else { return }
        actions[index] = action
        save()
    }

    func remove(id: CustomAction.ID) {
        actions.removeAll { $0.id == id }
        save()
    }

    /// Moves the action at `index` one place up (−1) or down (+1).
    func move(at index: Int, by offset: Int) {
        let target = index + offset
        guard actions.indices.contains(index), actions.indices.contains(target) else { return }
        actions.swapAt(index, target)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
