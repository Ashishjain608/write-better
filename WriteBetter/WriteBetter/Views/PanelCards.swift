import SwiftUI

// MARK: - C7 Result canvas

/// The hero surface. One `Text`, one string, never a `ForEach` and never a lazy
/// container — the measured cause of streaming lag is CoreText re-laying out a
/// growing `Text`, and splitting it makes that dramatically worse (§11.2 pitfall 6).
struct ResultCanvas: View {
    let text: String
    var isStreaming: Bool = false
    var strokeTint: Color? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caretVisible = true
    @State private var contentHeight: CGFloat = 0
    @State private var bottomOffset: CGFloat = 0

    private static let bottomAnchor = "resultBottom"
    private static let space = "resultScroll"
    private static let minHeight: CGFloat = 132
    private static let maxHeight: CGFloat = 300

    private var canvasHeight: CGFloat {
        min(max(contentHeight, Self.minHeight), Self.maxHeight)
    }

    /// True once the reader has scrolled away from the tail — auto-scroll then stops
    /// fighting them.
    private var userScrolledUp: Bool { bottomOffset > canvasHeight + 8 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    styledText
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(14)
                        .background(heightProbe)

                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchor)
                        .background(bottomProbe)
                }
            }
            .coordinateSpace(name: Self.space)
            .onChange(of: text) { _, _ in
                guard isStreaming, !userScrolledUp else { return }
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
        .frame(height: canvasHeight)
        // The canvas is a Text, so it takes no focus by default — a keyboard-only
        // user could never reach it to scroll a long rewrite. §7.1 puts it second
        // in the Tab sequence.
        .focusable()
        .sunkenSurface(stroke: strokeTint)
        .onPreferenceChange(ResultContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(ResultBottomOffsetKey.self) { bottomOffset = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Improved text")
        .accessibilityValue(text.isEmpty ? "Empty" : text)
        .modifier(UpdatesFrequently(isActive: isStreaming))
        // M6: 900 ms blink. `.task(id:)` tears the loop down when streaming stops
        // or the panel closes.
        .task(id: isStreaming) {
            guard isStreaming, !reduceMotion else {
                caretVisible = true
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(450))
                caretVisible.toggle()
            }
        }
    }

    /// `Text(result) + caret` — the caret is a glyph in the same text run, so it
    /// lands after the final character of the wrapped last line for free.
    private var styledText: some View {
        (Text(text) + caret)
            .font(Theme.Font.result)
            .foregroundStyle(Theme.Color.textPrimary)
            .lineSpacing(Theme.TextStyle.result.lineSpacing)
            .textSelection(.enabled)
    }

    private var caret: Text {
        guard isStreaming else { return Text(verbatim: "") }
        // Solid and non-blinking under Reduce Motion — the indicator carries meaning,
        // so it is preserved as a static form rather than removed (§10).
        let opacity = (reduceMotion || caretVisible) ? 1.0 : 0.15
        return Text(verbatim: "▌").foregroundColor(Theme.Color.streaming.opacity(opacity))
    }

    private var heightProbe: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ResultContentHeightKey.self, value: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    /// §11.2 pitfall 14: nothing hit-testable may be added inside this scroll view.
    private var bottomProbe: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ResultBottomOffsetKey.self,
                                   value: proxy.frame(in: .named(Self.space)).maxY)
        }
        .allowsHitTesting(false)
    }
}

private struct ResultContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ResultBottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// `.updatesFrequently` tells VoiceOver the value is changing, without announcing
/// every token (§10).
private struct UpdatesFrequently: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        if isActive {
            content.accessibilityAddTraits(.updatesFrequently)
        } else {
            content
        }
    }
}

// MARK: - Cut-off notice

/// Shown with a partial result the provider stopped short of finishing. The text stays
/// copyable; the wording says why Replace is gone so the missing button isn't a mystery.
struct CutOffNotice: View {
    let error: AIServiceError

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(error.errorDescription ?? "The result was cut off.")
                    .textStyle(.label)
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion).textStyle(.caption)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "scissors")
        }
        .foregroundStyle(Theme.Color.warning)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Error card (§7.1)

/// Fills the result canvas. Renders `errorDescription` then `recoverySuggestion` —
/// never a raw `localizedDescription`, never an HTTP status code.
struct ErrorCard<Extra: View>: View {
    private let symbol: String
    private let tint: Color
    private let title: String
    private let suggestion: String?
    private let countdown: Int?
    private let extra: Extra

    init(symbol: String,
         tint: Color,
         title: String,
         suggestion: String?,
         countdown: Int? = nil,
         @ViewBuilder extra: () -> Extra) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.suggestion = suggestion
        self.countdown = countdown
        self.extra = extra()
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title)
                    .textStyle(.body)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let suggestion {
                    Text(suggestion)
                        .textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let countdown {
                    Text("Retry in \(countdown)s")
                        .textStyle(.caption)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(Theme.Motion.curve(.snappy(duration: 0.22), reduceMotion: reduceMotion),
                                   value: countdown)
                }
                extra.padding(.top, Theme.Space.sm)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(tint.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .sunkenSurface(stroke: tint.opacity(0.45))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) \(suggestion ?? "")")
    }
}

extension ErrorCard where Extra == EmptyView {
    init(symbol: String, tint: Color, title: String, suggestion: String?, countdown: Int? = nil) {
        self.init(symbol: symbol, tint: tint, title: title,
                  suggestion: suggestion, countdown: countdown) { EmptyView() }
    }
}

// MARK: - Inline key field

/// Shared by the Setup card and the invalid-key card. A `SecureField`, so VoiceOver
/// never reads the key aloud and nothing is ever logged.
struct InlineKeyField: View {
    let provider: AIProvider
    @Binding var key: String
    let isValidating: Bool
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        SecureField(provider.keyPlaceholder, text: $key)
            .textFieldStyle(.plain)
            .font(Theme.Font.mono)
            .foregroundStyle(Theme.Color.textPrimary)
            .focused($isFocused)
            .onSubmit(onSubmit)
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 32)
            .sunkenSurface(radius: Theme.Radius.control,
                           stroke: isFocused ? provider.accent.opacity(0.7) : nil)
            .focusRing(isFocused, radius: Theme.Radius.control)
            .accessibilityLabel("\(provider.displayName) API key")
            .disabled(isValidating)
            .onAppear { isFocused = true }
            .onChange(of: provider) { _, _ in isFocused = true }
    }
}

// MARK: - Setup card (§7.1 no-API-key state)

/// The panel's own first-run path: pick a provider, paste a key, run — without ever
/// leaving the panel.
struct SetupCard: View {
    let providers: [AIProvider]
    let selected: AIProvider
    let configured: Set<AIProvider>
    @Binding var key: String
    let isValidating: Bool
    let errorText: String?
    let onSelect: (AIProvider) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            SectionHeader("Get started")

            // 7 chips don't fit one row at 560pt: wrap into rows of ~4.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: Theme.Space.md)], spacing: Theme.Space.md) {
                ForEach(providers) { provider in
                    Button { onSelect(provider) } label: {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: provider.iconSymbol)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(provider.accent)
                            Text(provider.shortName)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            if configured.contains(provider) && provider.needsAPIKey {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.Color.success)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: provider == selected))
                    .accessibilityLabel(provider.displayName)
                    .accessibilityHint(configured.contains(provider)
                                       ? (provider.needsAPIKey ? "Key saved" : "Ready")
                                       : (provider.needsAPIKey ? "Needs an API key" : "Set up in Settings"))
                    .accessibilityAddTraits(provider == selected ? [.isSelected] : [])
                }
            }

            if selected.needsAPIKey {
                InlineKeyField(provider: selected, key: $key, isValidating: isValidating, onSubmit: onSubmit)
            } else {
                // No key to paste: a server address is entered in Settings → Providers.
                Text("\(selected.displayName) is set up in Settings → Providers (⌘,).")
                    .textStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selected.needsAPIKey {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.md) {
                    Text("Stored in your Mac's Keychain. Never leaves your device.")
                        .textStyle(.caption)
                    Spacer(minLength: Theme.Space.md)
                    ConsoleLink(provider: selected)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .sunkenSurface()
    }
}

/// "Get a key ↗" — one component so the wording and the accessibility label never drift.
struct ConsoleLink: View {
    let provider: AIProvider
    var title: String = "Get a key"

    var body: some View {
        Link(destination: provider.consoleURL) {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
            }
        }
        .textStyle(.caption)
        .foregroundStyle(Theme.Color.accentText)
        .help("Opens \(provider.displayName)'s console in your browser")
        .accessibilityLabel("\(title) for \(provider.displayName), opens in your browser")
    }
}

// MARK: - Empty-input card (§7.1)

struct EmptyInputCard: View {
    var body: some View {
        VStack(spacing: Theme.Space.md) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.Color.textTertiary)
                .accessibilityHidden(true)
            Text("Nothing to improve").textStyle(.label)
            Text("Copy some text with ⌘C, then press ⇧⌘Space.").textStyle(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .sunkenSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nothing to improve. Copy some text, then press Shift Command Space.")
    }
}

// MARK: - C6 Source strip

struct SourceStrip: View {
    let text: String
    let truncated: Bool
    let isExpanded: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Theme.Color.textTertiary.opacity(0.35))
                .frame(width: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(text)
                    .textStyle(.source)
                    .lineLimit(isExpanded ? 8 : 2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if truncated {
                    Label("Only the first 20,000 characters were used.",
                          systemImage: "exclamationmark.circle.fill")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.warning)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(Theme.Space.lg)
        .sunkenSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Original text")
        .accessibilityValue(text)
        .accessibilityHint("Double tap to expand")
    }
}

// MARK: - Previews

#Preview("Result canvas — streaming") {
    ResultCanvas(text: "This is a test passage that needs improvement and should be made better. I wrote it quickly, and it shows.",
                 isStreaming: true,
                 strokeTint: Theme.Color.streaming.opacity(0.35))
        .padding(Theme.Space.xl)
        .frame(width: 560)
        .background(Theme.Color.surface)
}

#Preview("Error cards") {
    VStack(spacing: Theme.Space.lg) {
        ErrorCard(symbol: "wifi.slash",
                  tint: Theme.Color.danger,
                  title: "You're offline.",
                  suggestion: "Reconnect and press ⌘R.")

        ErrorCard(symbol: "hourglass",
                  tint: Theme.Color.warning,
                  title: "Rate limited — too many requests.",
                  suggestion: "Wait a few seconds and try again.",
                  countdown: 14)

        EmptyInputCard()

        SourceStrip(text: "this is a test text that needs improvement and should be made better, i wrote it fast and it shows",
                    truncated: true,
                    isExpanded: false)
    }
    .padding(Theme.Space.xl)
    .frame(width: 560)
    .background(Theme.Color.surface)
}

#Preview("Cut-off notice") {
    CutOffNotice(error: .cutOff(hitLimit: true))
        .padding(Theme.Space.xl)
        .frame(width: 560)
        .background(Theme.Color.surface)
}

#Preview("Setup card — no API key") {
    SetupCard(providers: AIProvider.allCases,
              selected: .anthropic,
              configured: [.gemini],
              key: .constant(""),
              isValidating: false,
              errorText: nil,
              onSelect: { _ in },
              onSubmit: {})
        .padding(Theme.Space.xl)
        .frame(width: 560)
        .background(Theme.Color.surface)
}
