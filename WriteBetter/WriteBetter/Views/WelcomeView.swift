import AppKit
import SwiftUI

/// First run (§9.2). One scrolling page, four blocks, no wizard steps — everything
/// visible at once so the user can see the finish line. Budgeted at ~37 seconds.
struct WelcomeView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @StateObject private var sample = ImprovementController()

    let onFinish: () -> Void

    @State private var chosenProvider: AIProvider?
    @State private var keyDraft = ""
    @State private var verification: Verification = .idle
    @State private var sampleText = "i think we should probly move the meeting, lmk"
    @State private var validationTask: Task<Void, Never>?
    @FocusState private var keyFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Verification {
        case idle, checking, verified, failed(String)

        var isChecking: Bool { if case .checking = self { return true }; return false }
        var isVerified: Bool { if case .verified = self { return true }; return false }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.h1) {
                    hero
                    blockOne
                    blockTwo.id("block2")
                    blockThree.id("block3")
                    blockOptional
                    footer
                }
                .padding(.horizontal, Theme.Space.h2)
                .padding(.vertical, Theme.Space.h1)
            }
            .onChange(of: verification.isVerified) { _, verified in
                guard verified else { return }
                withAnimation(Theme.Motion.curve(Theme.Motion.enter, reduceMotion: reduceMotion)) {
                    proxy.scrollTo("block3", anchor: .top)
                }
            }
        }
        .frame(width: 560, height: 620)
        .glassSurface(cornerRadius: Theme.Radius.panel)
        .onAppear {
            chosenProvider = settings.configuredProviders.first ?? settings.selectedProvider
            sample.load(text: sampleText)
            accessibility.beginPolling()
        }
        .onDisappear { accessibility.endPolling() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to WriteBetter")
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: Theme.Space.md) {
            BrandMark(size: 64)
            Wordmark(size: 22)
            HStack(spacing: Theme.Space.sm) {
                Text("Select text anywhere. Press").textStyle(.subtitle)
                ForEach(HotkeyManager.displayKeys, id: \.self) { Keycap(symbol: $0) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Select text anywhere, then press Shift Command Space")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 1 — provider

    private var blockOne: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            StepHeader(index: 1, title: "Pick a provider")
            HStack(spacing: Theme.Space.lg) {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        chosenProvider = provider
                        settings.selectedProvider = provider
                        verification = .idle
                        keyDraft = ""
                        DispatchQueue.main.async { keyFocused = true }
                    } label: {
                        VStack(spacing: Theme.Space.sm) {
                            Image(systemName: provider.iconSymbol)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(provider.accent)
                            Text(provider.displayName)
                                .textStyle(.label)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Text(provider.modelFamilyName).textStyle(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                    }
                    .buttonStyle(WelcomeTileStyle(isSelected: chosenProvider == provider))
                    .accessibilityLabel("\(provider.displayName), \(provider.modelFamilyName)")
                    .accessibilityAddTraits(chosenProvider == provider ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: 2 — key

    private var blockTwo: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            StepHeader(index: 2, title: "Paste your key")

            HStack(spacing: Theme.Space.lg) {
                SecureField(activeProvider.keyPlaceholder, text: $keyDraft)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.mono)
                    .foregroundStyle(Theme.Color.textPrimary)
                    .focused($keyFocused)
                    .onSubmit(verifyKey)
                    .padding(.horizontal, Theme.Space.lg)
                    .frame(height: 36)
                    .sunkenSurface(radius: Theme.Radius.control,
                                   stroke: keyFocused ? activeProvider.accent.opacity(0.7) : nil)
                    .focusRing(keyFocused, radius: Theme.Radius.control, reduceMotion: reduceMotion)
                    .accessibilityLabel("\(activeProvider.displayName) API key")

                Button(action: verifyKey) {
                    HStack(spacing: Theme.Space.sm) {
                        if verification.isChecking {
                            ProgressView().controlSize(.small)
                            Text("Checking…")
                        } else if verification.isVerified {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Verified")
                        } else {
                            Text("Continue")
                        }
                    }
                    .frame(minWidth: 84)
                }
                .buttonStyle(PrimaryButtonStyle(minWidth: 110))
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || verification.isChecking)
            }
            .disabled(chosenProvider == nil)
            .opacity(chosenProvider == nil ? 0.45 : 1)

            if case .failed(let message) = verification {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Space.md) {
                Text("Don't have one?").textStyle(.caption)
                ConsoleLink(provider: activeProvider)
                Text("·").textStyle(.caption)
                Text("Stored in Keychain").textStyle(.caption)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: 3 — try it

    private var blockThree: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            StepHeader(index: 3, title: "Try it")

            TextField("", text: $sampleText, axis: .vertical)
                .textFieldStyle(.plain)
                .textStyle(.source)
                .lineLimit(1...3)
                .padding(Theme.Space.lg)
                .sunkenSurface()
                .accessibilityLabel("Sample text to improve")

            HStack {
                Spacer(minLength: 0)
                Button {
                    sample.load(text: sampleText)
                    sample.run(action: nil, customPrompt: nil)
                } label: {
                    Label("Improve this", systemImage: "sparkles")
                }
                .buttonStyle(PrimaryButtonStyle(minWidth: 140))
                .disabled(!isConfigured || sample.phase.isBusy)
            }

            if sample.phase.isBusy || sample.hasResult {
                ResultCanvas(text: sample.displayText,
                             isStreaming: sample.phase.isStreaming,
                             strokeTint: sample.phase.isStreaming
                                ? Theme.Color.streaming.opacity(0.35) : nil)
            }

            if case .done = sample.phase {
                HStack(spacing: Theme.Space.sm) {
                    Text("That's it. Anywhere on your Mac: copy text, press").textStyle(.caption)
                    ForEach(HotkeyManager.displayKeys, id: \.self) { Keycap(symbol: $0) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("That's it. Anywhere on your Mac, copy text and press Shift Command Space.")
            }
        }
        .opacity(isConfigured ? 1 : 0.45)
        .disabled(!isConfigured)
    }

    // MARK: Optional — Accessibility

    @ViewBuilder
    private var blockOptional: some View {
        if !accessibility.isSandboxed {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                StepHeader(index: nil, title: "Optional")

                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accessibility.isTrusted ? Theme.Color.success : Theme.Color.warning)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text(accessibility.isTrusted ? "Replace in place is on" : "Replace text in place")
                            .textStyle(.label)
                        Text(accessibility.isTrusted
                             ? "WriteBetter can paste results straight back into your app."
                             : """
                               Needs Accessibility access. Everything else works without it.
                               """)
                            .textStyle(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: Theme.Space.lg)

                    if accessibility.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .textStyle(.caption)
                            .foregroundStyle(Theme.Color.success)
                    } else {
                        // §9.3 rule 1 — a direct click is the only path to the prompt.
                        Button("Enable…") { accessibility.requestAccess() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(Theme.Space.lg)
                .cardSurface()

                if !accessibility.isTrusted {
                    Button("Open System Settings") { accessibility.openSystemSettings() }
                        .buttonStyle(.link)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.accentText)
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: Theme.Space.lg) {
            Spacer(minLength: 0)
            Button("Skip for now") { onFinish() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Done") { onFinish() }
                .buttonStyle(PrimaryButtonStyle(minWidth: 96))
                .disabled(!isConfigured)
        }
    }

    // MARK: Helpers

    private var activeProvider: AIProvider { chosenProvider ?? settings.selectedProvider }

    private var isConfigured: Bool {
        verification.isVerified || settings.hasKey(for: activeProvider)
    }

    private func verifyKey() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        let provider = activeProvider

        verification = .checking
        validationTask?.cancel()
        validationTask = Task { @MainActor in
            let modelID = settings.modelID(for: provider)
            let service = AIServiceFactory.service(for: provider, apiKey: key, modelID: modelID)
            let result = await service.validateKey()
            if Task.isCancelled { return }

            switch result {
            case .success:
                settings.setAPIKey(key, for: provider)
                settings.selectedProvider = provider
                keyDraft = ""
                verification = .verified
            case .failure(let error):
                verification = .failed(error.recoverySuggestion ?? error.errorDescription ?? "That key was rejected.")
            }
        }
    }
}

// MARK: - Pieces

private struct StepHeader: View {
    let index: Int?
    let title: String

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            if let index {
                Text("\(index)")
                    .textStyle(.badge)
                    .foregroundStyle(Theme.Color.accentText)
                    .frame(width: 18, height: 18)
                    .background(Theme.Color.accentMuted, in: Circle())
                    .monospacedDigit()
            }
            Text(title.uppercased()).textStyle(.sectionHeader)
            Rectangle()
                .fill(Theme.Color.stroke)
                .frame(height: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(index.map { "Step \($0), \(title)" } ?? title)
    }
}

private struct WelcomeTileStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(isSelected ? Theme.Color.accentMuted : Theme.Color.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? Theme.Color.accent : Theme.Color.stroke,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
    }
}

#Preview("Welcome") {
    WelcomeView(settings: .shared, onFinish: {})
        .background(Theme.Color.bgBase)
}
