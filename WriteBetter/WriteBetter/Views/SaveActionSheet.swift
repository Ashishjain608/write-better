import SwiftUI

/// "Save as action" from the ⌘K prompt bar: a modal card over the panel that
/// reuses the Settings editor, prefilled from the typed instruction. When all
/// four slots are taken it says so instead.
struct SaveActionSheet: View {
    let instruction: String
    @ObservedObject var store: CustomActionStore
    let onDismiss: () -> Void
    /// Called with the ⌘ digit the new action landed on.
    let onSaved: (Int) -> Void

    var body: some View {
        ZStack {
            Theme.Color.scrim
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            Group {
                if store.isFull {
                    full
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Save as action").textStyle(.title)
                            .padding([.top, .horizontal], Theme.Space.lg)
                        ActionEditor(
                            original: CustomAction(name: CustomAction.suggestedName(for: instruction),
                                                   instruction: String(instruction.prefix(CustomAction.instructionLimit))),
                            onSave: { action in
                                if store.add(action) { onSaved(store.actions.count + 4) }
                            },
                            onCancel: onDismiss)
                    }
                }
            }
            .frame(width: 400)
            .raisedSurface(radius: Theme.Radius.panel)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Save as action")
        .accessibilityAddTraits(.isModal)
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("All \(CustomAction.maxCount) slots are used").textStyle(.title)
            Text("Remove one in Settings \u{2192} Actions to save this instruction.")
                .textStyle(.caption)
            HStack(spacing: Theme.Space.md) {
                Spacer()
                Button("Close", action: onDismiss)
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Open Settings") {
                    SettingsRouter.shared.tab = .actions
                    SettingsRouter.shared.open()
                    onDismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.Space.xxl)
    }
}
