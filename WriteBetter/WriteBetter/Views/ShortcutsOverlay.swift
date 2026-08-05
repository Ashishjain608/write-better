import SwiftUI

/// The `?` overlay. Every binding in §7.1 is listed here, so a keyboard user can
/// discover the whole map without leaving the app or reading documentation (§10).
struct ShortcutsOverlay: View {
    @Binding var isPresented: Bool

    /// Built from `QuickAction.allCases`, so the ⌘1…⌘n row is always accurate.
    private var rows: [(String, String)] {
        var entries: [(String, String)] = [
            ("esc",  "Stop generating, or close the panel"),
            ("↩",    "Copy the result and close"),
            ("⇧↩",   "Copy the result and stay"),
            ("⌘↩",   "Replace in place (needs Accessibility)"),
            ("⌘C",   "Copy the selection inside the result"),
            ("⌘R",   "Regenerate"),
            ("⌘K",   "Focus the instruction field"),
            ("⌘⌫",   "Clear the instruction field"),
        ]
        let actionCount = QuickAction.allCases.count
        if actionCount > 0 {
            let range = actionCount == 1 ? "⌘1" : "⌘1…⌘\(min(actionCount, 9))"
            entries.append((range, "Run a quick action"))
        }
        entries.append(("⌘] / ⌘[", "Next / previous configured provider"))
        entries.append(("⌘,", "Open Settings"))
        entries.append(("Tab", "Move focus"))
        entries.append(("?", "Show or hide this list"))
        return entries
    }

    var body: some View {
        ZStack {
            Theme.Color.scrim
                .contentShape(Rectangle())
                .onTapGesture { isPresented = false }

            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack {
                    Text("Keyboard").textStyle(.title)
                    Spacer()
                    Button { isPresented = false } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle())
                        .help("Close (esc)")
                        .accessibilityLabel("Close shortcuts")
                }

                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.lg) {
                            Keycap(symbol: row.0)
                                .frame(width: 72, alignment: .leading)
                            Text(row.1).textStyle(.caption)
                            Spacer(minLength: 0)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.1), \(row.0)")
                    }
                }
            }
            .padding(Theme.Space.xxl)
            .frame(width: 420)
            .raisedSurface(radius: Theme.Radius.panel)
        }
        .transition(.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcuts")
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("Shortcuts overlay") {
    ShortcutsOverlay(isPresented: .constant(true))
        .frame(width: 560, height: 520)
        .background(Theme.Color.bgBase)
}
