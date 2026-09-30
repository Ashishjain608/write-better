import SwiftUI

/// Actions tab: the user's saved instructions. They run in the panel after the
/// built-in quick actions, on ⌘6–⌘9, in the order shown here. Everything
/// applies immediately — no Save-the-pane button (§7.2).
struct ActionsSettingsView: View {
    @ObservedObject var store: CustomActionStore = .shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The row being edited, or nil. Only one editor is open at a time.
    @State private var editingID: CustomAction.ID?
    @State private var isAdding = false
    /// Held so "Undo" can put a deleted action back where it was.
    @State private var removed: (action: CustomAction, index: Int)?

    var body: some View {
        SettingsPane {
            SettingsGroup("Saved actions") {
                if store.actions.isEmpty && !isAdding {
                    emptyState
                } else {
                    ForEach(Array(store.actions.enumerated()), id: \.element.id) { index, action in
                        if index > 0 { SettingsDivider() }
                        if editingID == action.id {
                            ActionEditor(original: action, onSave: store.update, onCancel: closeEditor)
                        } else {
                            row(action, at: index)
                        }
                    }
                    if isAdding {
                        if !store.actions.isEmpty { SettingsDivider() }
                        ActionEditor(original: nil,
                                     onSave: { store.add($0); closeEditor() },
                                     onCancel: closeEditor)
                    }
                }
            }

            footer

            if let removed {
                undoPill(for: removed.action)
            }
        }
        .animation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion), value: store.actions)
        .animation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion), value: editingID)
        .animation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion), value: isAdding)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("No saved actions yet").textStyle(.label)
                Text("Save an instruction you use often, then run it from the panel with one key. Add an example, or write your own.")
                    .textStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Theme.Space.md) {
                ForEach(CustomAction.starters) { starter in
                    Button {
                        store.add(starter)
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            if let icon = starter.icon {
                                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                            }
                            Text(starter.name).lineLimit(1)
                        }
                    }
                    .buttonStyle(ChipButtonStyle(height: 30))
                    .help(starter.instruction)
                    .accessibilityLabel("Add \(starter.name)")
                    .accessibilityHint(starter.instruction)
                }
            }
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Row

    private func row(_ action: CustomAction, at index: Int) -> some View {
        let digit = CustomAction.shortcutDigit(at: index) ?? 0
        return HStack(spacing: Theme.Space.md) {
            Button { edit(action) } label: {
                HStack(spacing: Theme.Space.lg) {
                    Keycap(symbol: "⌘\(digit)")
                    Image(systemName: action.icon ?? "text.quote")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(action.icon == nil ? Theme.Color.textTertiary : Theme.Color.textSecondary)
                        .frame(width: 16)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(action.name).textStyle(.label).lineLimit(1)
                        Text(action.instruction).textStyle(.caption).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit")
            .accessibilityLabel("\(action.name), Command \(digit)")
            .accessibilityHint("Edits this action")

            if store.actions.count > 1 {
                Button { store.move(at: index, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(index == 0)
                    .help("Move up")
                    .accessibilityLabel("Move \(action.name) up")
                Button { store.move(at: index, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(IconButtonStyle())
                    .disabled(index == store.actions.count - 1)
                    .help("Move down")
                    .accessibilityLabel("Move \(action.name) down")
            }
            Button { delete(action, at: index) } label: { Image(systemName: "trash") }
                .buttonStyle(IconButtonStyle())
                .help("Delete")
                .accessibilityLabel("Delete \(action.name)")
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(minHeight: 52)
        .contextMenu {
            Button("Edit") { edit(action) }
            Button("Move Up") { store.move(at: index, by: -1) }.disabled(index == 0)
            Button("Move Down") { store.move(at: index, by: 1) }.disabled(index == store.actions.count - 1)
            Divider()
            Button("Delete") { delete(action, at: index) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            Text(footerText)
                .textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.lg)
            Button {
                editingID = nil
                isAdding = true
            } label: {
                Label("New action", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(store.isFull || isAdding)
        }
    }

    private var footerText: String {
        let range = "⌘\(CustomAction.shortcutDigit(at: 0) ?? 6)–⌘9"
        if store.isFull {
            return "All \(CustomAction.maxCount) slots are in use (\(range)). Delete one to add another."
        }
        return """
        In the panel, saved actions follow the built-in ones and run with \(range), \
        in this order. You can also save what you type in the panel's ⌘K bar.
        """
    }

    // MARK: Undo

    private func undoPill(for action: CustomAction) -> some View {
        HStack(spacing: Theme.Space.lg) {
            Label("Deleted \u{201C}\(action.name)\u{201D}.", systemImage: "trash")
                .textStyle(.caption)
            Spacer(minLength: Theme.Space.lg)
            Button("Undo") {
                if let removed { store.add(removed.action, at: removed.index) }
                removed = nil
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(store.isFull)
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .cardSurface(radius: Theme.Radius.control)
        .transition(.opacity)
    }

    // MARK: Actions

    private func edit(_ action: CustomAction) {
        isAdding = false
        editingID = action.id
    }

    private func closeEditor() {
        editingID = nil
        isAdding = false
    }

    private func delete(_ action: CustomAction, at index: Int) {
        if editingID == action.id { editingID = nil }
        store.remove(id: action.id)
        removed = (action, index)
    }
}

// MARK: - Editor

/// Name, glyph and instruction for one action, edited in place inside the group.
private struct ActionEditor: View {
    let original: CustomAction?
    let onSave: (CustomAction) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @State private var instruction: String
    @State private var icon: String?
    @FocusState private var focus: Field?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case name, instruction }

    init(original: CustomAction?,
         onSave: @escaping (CustomAction) -> Void,
         onCancel: @escaping () -> Void) {
        self.original = original
        self.onSave = onSave
        self.onCancel = onCancel
        _name = State(initialValue: original?.name ?? "")
        _instruction = State(initialValue: original?.instruction ?? "")
        _icon = State(initialValue: original?.icon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Name").textStyle(.label)
                HStack(spacing: Theme.Space.md) {
                    iconMenu
                    TextField("Translate to Spanish", text: $name)
                        .textFieldStyle(.plain)
                        .textStyle(.body)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .focused($focus, equals: .name)
                        .onChange(of: name) { _, value in
                            if value.count > CustomAction.nameLimit { name = String(value.prefix(CustomAction.nameLimit)) }
                        }
                        .onSubmit { focus = .instruction }
                        .padding(.horizontal, Theme.Space.lg)
                        .frame(height: 32)
                        .sunkenSurface(radius: Theme.Radius.control)
                        .focusRing(focus == .name, radius: Theme.Radius.control, reduceMotion: reduceMotion)
                        .accessibilityLabel("Name")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text("Instruction").textStyle(.label)
                TextEditor(text: $instruction)
                    .scrollContentBackground(.hidden)
                    .textStyle(.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .focused($focus, equals: .instruction)
                    .onChange(of: instruction) { _, value in
                        if value.count > CustomAction.instructionLimit {
                            instruction = String(value.prefix(CustomAction.instructionLimit))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if instruction.isEmpty {
                            Text("Say what to do, as you'd ask a colleague: \u{201C}Translate to Spanish and keep it formal.\u{201D}")
                                .textStyle(.body)
                                .foregroundStyle(Theme.Color.textTertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(Theme.Space.md)
                    .frame(height: 96)
                    .sunkenSurface(radius: Theme.Radius.control)
                    .focusRing(focus == .instruction, radius: Theme.Radius.control, reduceMotion: reduceMotion)
                    .accessibilityLabel("Instruction")
                HStack {
                    Spacer()
                    Text("\(instruction.count)/\(CustomAction.instructionLimit)")
                        .textStyle(.caption)
                        .monospacedDigit()
                        .accessibilityLabel("\(instruction.count) of \(CustomAction.instructionLimit) characters")
                }
            }

            HStack(spacing: Theme.Space.md) {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!isValid)
            }
        }
        .padding(Theme.Space.lg)
        .onAppear { focus = .name }
    }

    private var iconMenu: some View {
        Menu {
            Button("No icon") { icon = nil }
            Divider()
            ForEach(CustomAction.iconChoices, id: \.self) { symbol in
                Button { icon = symbol } label: {
                    Label(symbol.replacingOccurrences(of: ".", with: " "), systemImage: symbol)
                }
            }
        } label: {
            Image(systemName: icon ?? "square.dashed")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(icon == nil ? Theme.Color.textTertiary : Theme.Color.textPrimary)
                .frame(width: 32, height: 32)
                .sunkenSurface(radius: Theme.Radius.control)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose an icon")
        .accessibilityLabel("Icon")
        .accessibilityValue(icon?.replacingOccurrences(of: ".", with: " ") ?? "None")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedInstruction: String { instruction.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isValid: Bool { !trimmedName.isEmpty && !trimmedInstruction.isEmpty }

    private func save() {
        guard isValid else { return }
        var action = original ?? CustomAction(name: "", instruction: "")
        action.name = trimmedName
        action.instruction = trimmedInstruction
        action.icon = icon
        onSave(action)
        onCancel()
    }
}

#Preview("Actions — empty") {
    ActionsSettingsView(store: CustomActionStore(defaults: UserDefaults(suiteName: "preview.actions.empty")!))
        .frame(width: 560, height: 420)
}

#Preview("Actions — filled") {
    let store = CustomActionStore(defaults: UserDefaults(suiteName: "preview.actions.filled")!)
    if store.actions.isEmpty {
        CustomAction.starters.forEach { store.add($0) }
        store.add(CustomAction(name: "Reply to a customer", instruction: "Rewrite as a friendly reply to a customer."))
    }
    return ActionsSettingsView(store: store)
        .frame(width: 560, height: 520)
}
