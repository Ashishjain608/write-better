import SwiftUI

/// Providers tab (§7.2). Everything applies immediately — no Save button.
struct ProvidersSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var router: SettingsRouter

    /// The key we just removed, held so "Undo" can put it back. Never logged.
    @State private var removedKey: (provider: AIProvider, key: String)?

    var body: some View {
        SettingsPane {
            if settings.configuredProviders.isEmpty {
                noProviderBanner
            }

            defaultProviderPicker

            if settings.configuredProviders.count >= 2 {
                Text("Switch in the panel with ⌘[ and ⌘].")
                    .textStyle(.caption)
            }

            VStack(spacing: Theme.Space.lg) {
                ForEach(AIProvider.allCases) { provider in
                    ProviderRow(provider: provider,
                                settings: settings,
                                isExpanded: router.expandedProvider == provider,
                                focusRequest: router.focusRequest,
                                onToggleExpand: { toggle(provider) },
                                onRemoveKey: { remove(provider) })
                }
            }

            if case .unavailable(let reason) = AppleIntelligence.availability {
                appleUnavailableNote(reason)
            }

            if let removedKey {
                undoPill(for: removedKey)
            }
        }
        .onAppear { settings.refreshProviderAvailability() }
    }

    /// Apple's on-device model is hidden everywhere it can't run; say why, once, here.
    private func appleUnavailableNote(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            Image(systemName: "cpu")
                .foregroundStyle(Theme.Color.textTertiary)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Apple on-device model unavailable").textStyle(.label)
                Text(reason).textStyle(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.lg)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    // MARK: Banner

    private var noProviderBanner: some View {
        HStack(alignment: .top, spacing: Theme.Space.lg) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Theme.Color.warning)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("No provider configured — WriteBetter can't run yet.")
                    .textStyle(.label)
                Text("Add a key for any provider below, or point WriteBetter at a local server.")
                    .textStyle(.caption)
            }
            Spacer(minLength: Theme.Space.lg)
            Button("Set up") {
                router.expandedProvider = AIProvider.allCases.first
                router.focusRequest &+= 1
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(Theme.Space.lg)
        .cardSurface(fill: Theme.Color.warning.opacity(0.10),
                     stroke: Theme.Color.warning.opacity(0.45))
        .accessibilityElement(children: .contain)
    }

    // MARK: Default-provider segmented row

    private var defaultProviderPicker: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader("Default provider")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Space.lg)],
                      spacing: Theme.Space.lg) {
                ForEach(AIProvider.allCases) { provider in
                    Button {
                        settings.selectedProvider = provider
                        if !settings.isUsable(provider) {
                            router.expandedProvider = provider
                            router.focusRequest &+= 1
                        }
                    } label: {
                        VStack(spacing: Theme.Space.xs) {
                            HStack(spacing: Theme.Space.sm) {
                                Image(systemName: settings.selectedProvider == provider
                                      ? "largecircle.fill.circle" : "circle")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(settings.selectedProvider == provider
                                                     ? Theme.Color.accent : Theme.Color.textTertiary)
                                Image(systemName: provider.iconSymbol)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(provider.accent)
                                Text(provider.shortName)
                                    .textStyle(.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            statusCaption(for: provider)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .buttonStyle(TileButtonStyle(isSelected: settings.selectedProvider == provider))
                    .accessibilityLabel(provider.displayName)
                    .accessibilityValue(settings.isUsable(provider) ? "Ready"
                                        : (provider.needsAPIKey ? "Needs a key" : "Needs a server address"))
                    .accessibilityAddTraits(settings.selectedProvider == provider ? [.isSelected] : [])
                }
            }
        }
    }

    private func statusCaption(for provider: AIProvider) -> some View {
        Group {
            if settings.isUsable(provider) {
                Label(provider.needsAPIKey ? "key" : (provider == .apple ? "on-device" : "server"),
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Color.success)
            } else {
                Label(provider.needsAPIKey ? "add key" : "add server",
                      systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.Color.warning)
            }
        }
        .textStyle(.caption)
        .font(.system(size: 11, weight: .regular))
    }

    // MARK: Undo

    private func undoPill(for removed: (provider: AIProvider, key: String)) -> some View {
        HStack(spacing: Theme.Space.lg) {
            Label("\(removed.provider.displayName) key removed.", systemImage: "trash")
                .textStyle(.caption)
            Spacer(minLength: Theme.Space.lg)
            Button("Undo") {
                settings.setAPIKey(removed.key, for: removed.provider)
                removedKey = nil
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, Theme.Space.lg)
        .padding(.vertical, Theme.Space.md)
        .cardSurface(radius: Theme.Radius.control)
        .transition(.opacity)
    }

    // MARK: Actions

    private func toggle(_ provider: AIProvider) {
        // Only one row is expanded at a time.
        router.expandedProvider = router.expandedProvider == provider ? nil : provider
    }

    private func remove(_ provider: AIProvider) {
        let key = settings.apiKey(for: provider)
        guard !key.isEmpty else { return }
        settings.setAPIKey("", for: provider)
        removedKey = (provider, key)
    }
}

// MARK: - Provider row

private struct ProviderRow: View {
    let provider: AIProvider
    @ObservedObject var settings: SettingsStore
    let isExpanded: Bool
    let focusRequest: Int
    let onToggleExpand: () -> Void
    let onRemoveKey: () -> Void

    enum TestState {
        case idle
        case testing
        case verified
        case invalid(String)
        case offline
    }

    @State private var draft: String = ""
    @State private var isEditingKey = false
    @State private var testState: TestState = .idle
    @State private var testTask: Task<Void, Never>?
    @State private var loadedModels: [String] = []
    @State private var isLoadingModels = false
    @State private var loadError: String?
    @State private var pickedOther = false
    @State private var otherDraft = ""
    @FocusState private var keyFieldFocused: Bool
    @FocusState private var otherFieldFocused: Bool
    @FocusState private var baseURLFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            header
            if isExpanded { expandedBody }
        }
        .padding(Theme.Space.lg)
        .background(alignment: .leading) {
            // 2pt leading rail in the provider's own accent, leading corners r12.
            UnevenRoundedRectangle(topLeadingRadius: Theme.Radius.card,
                                   bottomLeadingRadius: Theme.Radius.card,
                                   bottomTrailingRadius: 0,
                                   topTrailingRadius: 0,
                                   style: .continuous)
                .fill(provider.accent)
                .frame(width: 2)
                .accessibilityHidden(true)
        }
        .cardSurface(stroke: strokeColor)
        .contentShape(Rectangle())
        .onTapGesture { if !isExpanded { onToggleExpand() } }
        .contextMenu {
            if settings.hasKey(for: provider) {
                Button("Remove key", role: .destructive, action: onRemoveKey)
            }
        }
        .animation(Theme.Motion.curve(Theme.Motion.standard, reduceMotion: reduceMotion),
                   value: isExpanded)
        .onChange(of: focusRequest) { _, _ in
            guard isExpanded else { return }
            beginEditing()
        }
        .onAppear {
            syncDraft()
            if settings.usesCustomModelID(for: provider) { otherDraft = settings.modelID(for: provider) }
            if provider == .custom { otherDraft = settings.modelID(for: provider) }
        }
        .onChange(of: isExpanded) { _, expanded in if expanded { syncDraft() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(provider.displayName)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: settings.selectedProvider == provider
                  ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(settings.selectedProvider == provider
                                 ? Theme.Color.accent : Theme.Color.textTertiary)
                .accessibilityHidden(true)

            Text(provider.displayName).textStyle(.label)

            Spacer(minLength: Theme.Space.lg)

            badge

            if isExpanded, settings.hasKey(for: provider) {
                Button(action: onRemoveKey) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(TrashButtonStyle())
                .help("Remove the \(provider.displayName) key")
                .accessibilityLabel("Remove the \(provider.displayName) key")
            }

            Button(action: onToggleExpand) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .buttonStyle(.plain)
            .minimumHitTarget()
            .help(isExpanded ? "Collapse" : "Expand")
            .accessibilityLabel(isExpanded ? "Collapse \(provider.displayName)" : "Expand \(provider.displayName)")
        }
        .frame(minHeight: 24)
    }

    @ViewBuilder
    private var badge: some View {
        switch testState {
        case .testing:
            StatusPill(text: "Testing", tint: Theme.Color.accent, showsDot: true)
        case .verified:
            StatusPill(text: "Verified", tint: Theme.Color.success, systemImage: "checkmark.circle.fill")
        case .invalid:
            StatusPill(text: "Invalid", tint: Theme.Color.danger, systemImage: "exclamationmark.triangle.fill")
        case .offline:
            StatusPill(text: "Offline", tint: Theme.Color.warning, systemImage: "wifi.slash")
        case .idle:
            if settings.keyIsUnreadable(provider) {
                StatusPill(text: "Keychain locked", tint: Theme.Color.warning,
                           systemImage: "lock.fill")
            } else if settings.isUsable(provider) {
                StatusPill(text: provider.needsAPIKey ? "Key saved" : (provider == .apple ? "Ready" : "Server set"),
                           tint: Theme.Color.success, systemImage: "checkmark.circle.fill")
            } else {
                Text(provider.needsAPIKey ? "No key" : "No server").textStyle(.caption)
            }
        }
    }

    // MARK: Expanded body

    @ViewBuilder
    private var expandedBody: some View {
        if provider == .apple {
            Text("""
                 Runs on your Mac with Apple Intelligence: free, private, no key and no network. \
                 The model has a small context window, so it suits short selections best.
                 """)
                .textStyle(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            keyedBody
        }
    }

    private var keyedBody: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if provider == .custom { endpointSection }

            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Text(provider.needsAPIKey ? "API key" : "API key (optional)").textStyle(.caption)

                HStack(spacing: Theme.Space.md) {
                    keyField
                    Button(action: test) {
                        HStack(spacing: Theme.Space.sm) {
                            if case .testing = testState {
                                ProgressView().controlSize(.small)
                                Text("Testing…")
                            } else {
                                Text("Test")
                            }
                        }
                    }
                    .buttonStyle(SecondaryButtonStyle(minWidth: 84))
                    .disabled(isTesting || (provider.needsAPIKey ? effectiveKey.isEmpty : settings.customEndpointURL == nil))
                    .help(provider == .custom ? "Check the server address and key"
                                              : "Check this key against \(provider.displayName)")
                    .accessibilityLabel("Test the \(provider.displayName) key")
                }

                if let hint = prefixWarning {
                    Label(hint, systemImage: "exclamationmark.circle.fill")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.warning)
                }

                if case .invalid(let message) = testState {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if case .offline = testState {
                    Label("Reconnect and press Test again.", systemImage: "wifi.slash")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.warning)
                }

                HStack(spacing: Theme.Space.md) {
                    Text("Stored in Keychain.").textStyle(.caption)
                    if provider.needsAPIKey { ConsoleLink(provider: provider) }
                    Spacer(minLength: 0)
                }
            }

            if provider == .custom { customModelSection } else { modelSection }
        }
    }

    /// Catalog picker plus an "Other…" entry, so the curated list can never strand a user.
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.lg) {
                Text("Model").textStyle(.caption)
                Spacer(minLength: Theme.Space.lg)
                Picker("", selection: modelChoice) {
                    ForEach(provider.models) { model in
                        Text("\(model.name) · \(model.blurb)").tag(model.id)
                    }
                    Divider()
                    Text("Other…").tag(Self.otherTag)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 260)
                .accessibilityLabel("\(provider.displayName) model")
            }
            if showsOtherField {
                HStack(spacing: Theme.Space.md) {
                    TextField("Model id, e.g. \(provider.defaultModelID)", text: $otherDraft)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.mono)
                        .foregroundStyle(Theme.Color.textPrimary)
                        .focused($otherFieldFocused)
                        .onSubmit(commitOtherModel)
                        .onChange(of: otherFieldFocused) { _, focused in if !focused { commitOtherModel() } }
                        .padding(.horizontal, Theme.Space.lg)
                        .frame(height: 32)
                        .sunkenSurface(radius: Theme.Radius.control,
                                       stroke: otherFieldFocused ? provider.accent.opacity(0.7) : nil)
                        .accessibilityLabel("\(provider.displayName) model id")
                }
                Text("Sent exactly as typed. Newer models may need a newer WriteBetter.")
                    .textStyle(.caption)
            }
        }
    }

    // MARK: Custom endpoint

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                Text("Base URL").textStyle(.caption)
                Spacer(minLength: Theme.Space.md)
                Menu("Presets") {
                    ForEach(CustomEndpointService.presets) { preset in
                        Button(preset.name) {
                            settings.customBaseURL = preset.baseURL
                            testState = .idle
                            loadedModels = []
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Server presets")
            }
            TextField("http://localhost:11434/v1", text: $settings.customBaseURL)
                .textFieldStyle(.plain)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Color.textPrimary)
                .focused($baseURLFocused)
                .onChange(of: settings.customBaseURL) { _, _ in testState = .idle; loadedModels = [] }
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: 32)
                .sunkenSurface(radius: Theme.Radius.control,
                               stroke: baseURLFocused ? provider.accent.opacity(0.7) : nil)
                .accessibilityLabel("Custom endpoint base URL")
            if !settings.customBaseURL.trimmingCharacters(in: .whitespaces).isEmpty,
               settings.customEndpointURL == nil {
                Label("That doesn't look like a URL. Try http://localhost:11434/v1.",
                      systemImage: "exclamationmark.circle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.warning)
            } else {
                Text("Any server that speaks the OpenAI Chat Completions API: Ollama, LM Studio, OpenRouter…")
                    .textStyle(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.md) {
                Text("Model").textStyle(.caption)
                Spacer(minLength: Theme.Space.md)
                if !loadedModels.isEmpty {
                    Menu("\(loadedModels.count) models") {
                        ForEach(loadedModels, id: \.self) { id in
                            Button(id) { settings.setModelID(id, for: .custom); otherDraft = id }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Button(action: loadModels) {
                    HStack(spacing: Theme.Space.sm) {
                        if isLoadingModels { ProgressView().controlSize(.small) }
                        Text(isLoadingModels ? "Loading…" : "Load models")
                    }
                }
                .buttonStyle(SecondaryButtonStyle(minWidth: 110))
                .disabled(isLoadingModels || settings.customEndpointURL == nil)
                .help("Ask the server which models it has")
            }
            TextField("Model id, e.g. llama3.2", text: $otherDraft)
                .textFieldStyle(.plain)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Color.textPrimary)
                .focused($otherFieldFocused)
                .onSubmit(commitOtherModel)
                .onChange(of: otherFieldFocused) { _, focused in if !focused { commitOtherModel() } }
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: 32)
                .sunkenSurface(radius: Theme.Radius.control,
                               stroke: otherFieldFocused ? provider.accent.opacity(0.7) : nil)
                .accessibilityLabel("Custom endpoint model id")
            if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loadModels() {
        guard let base = settings.customEndpointURL else { return }
        isLoadingModels = true
        loadError = nil
        let key = effectiveKey
        Task { @MainActor in
            let service = CustomEndpointService(modelID: "", apiKey: key, baseURL: base)
            switch await service.fetchModelIDs() {
            case .success(let ids):
                loadedModels = ids
                if ids.isEmpty { loadError = "The server didn't list any models." }
            case .failure(let error):
                loadedModels = []
                loadError = [error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
            }
            isLoadingModels = false
        }
    }

    @ViewBuilder
    private var keyField: some View {
        if settings.hasKey(for: provider), !isEditingKey {
            HStack(spacing: Theme.Space.md) {
                Text(Self.mask(settings.apiKey(for: provider)))
                    .textStyle(.mono)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: Theme.Space.md)
                Button("Change") { beginEditing() }
                    .buttonStyle(.link)
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.accentText)
            }
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .sunkenSurface(radius: Theme.Radius.control)
            .accessibilityLabel("\(provider.displayName) API key, saved")
        } else {
            SecureField(provider.keyPlaceholder, text: $draft)
                .textFieldStyle(.plain)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Color.textPrimary)
                .focused($keyFieldFocused)
                .onSubmit(save)
                .onChange(of: draft) { _, _ in testState = .idle }
                // Saved on blur / Return rather than per keystroke, so a half-typed
                // key never reaches the Keychain.
                .onChange(of: keyFieldFocused) { _, focused in if !focused { save() } }
                .padding(.horizontal, Theme.Space.lg)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .sunkenSurface(radius: Theme.Radius.control,
                               stroke: keyFieldFocused ? provider.accent.opacity(0.7) : nil)
                .focusRing(keyFieldFocused, radius: Theme.Radius.control, reduceMotion: reduceMotion)
                .accessibilityLabel("\(provider.displayName) API key")
        }
    }

    // MARK: Derived

    private var effectiveKey: String {
        isEditingKey || !settings.hasKey(for: provider)
            ? draft.trimmingCharacters(in: .whitespacesAndNewlines)
            : settings.apiKey(for: provider)
    }

    private var isTesting: Bool {
        if case .testing = testState { return true }
        return false
    }

    /// A warning, never a block — the user may have a key shape we don't know about.
    private var prefixWarning: String? {
        guard let hint = provider.keyPrefixHint else { return nil }
        let key = effectiveKey
        guard !key.isEmpty, !key.hasPrefix(hint) else { return nil }
        return "That doesn't look like a \(hint)… key."
    }

    private static let otherTag = "__other__"

    /// True while "Other…" is chosen or the saved id isn't in the catalog.
    private var showsOtherField: Bool { pickedOther || settings.usesCustomModelID(for: provider) }

    private var modelChoice: Binding<String> {
        Binding(
            get: {
                showsOtherField ? Self.otherTag : settings.modelID(for: provider)
            },
            set: { choice in
                if choice == Self.otherTag {
                    pickedOther = true
                    otherDraft = settings.usesCustomModelID(for: provider) ? settings.modelID(for: provider) : ""
                    DispatchQueue.main.async { otherFieldFocused = true }
                } else {
                    pickedOther = false
                    settings.setModelID(choice, for: provider)
                }
            })
    }

    private func commitOtherModel() {
        let id = otherDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        settings.setModelID(id, for: provider)
        // Typing a catalog id by hand is the same as picking it.
        if provider.model(withID: id) != nil { pickedOther = false }
    }

    /// First 12 characters + bullets + last 4 — enough to recognise, never enough to use.
    static func mask(_ key: String) -> String {
        guard key.count > 20 else {
            return String(repeating: "•", count: max(8, key.count))
        }
        return "\(key.prefix(12))••••••••\(key.suffix(4))"
    }

    // MARK: Actions

    private func syncDraft() {
        if !settings.hasKey(for: provider) {
            isEditingKey = true
        } else {
            isEditingKey = false
            draft = ""
        }
    }

    private func beginEditing() {
        isEditingKey = true
        draft = ""
        testState = .idle
        DispatchQueue.main.async { keyFieldFocused = true }
    }

    /// macOS settings apply immediately — typing a key saves it.
    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.setAPIKey(trimmed, for: provider)
    }

    private func test() {
        let key = effectiveKey
        guard !key.isEmpty || !provider.needsAPIKey else { return }

        testTask?.cancel()
        testState = .testing

        testTask = Task { @MainActor in
            let modelID = settings.modelID(for: provider)
            let service = AIServiceFactory.service(for: provider, apiKey: key, modelID: modelID,
                                                   baseURL: settings.customEndpointURL)
            let result = await service.validateKey()
            if Task.isCancelled { return }

            switch result {
            case .success:
                testState = .verified
                if !key.isEmpty { settings.setAPIKey(key, for: provider) }
                isEditingKey = false
                draft = ""
                try? await Task.sleep(for: .seconds(2))
                if case .verified = testState, !Task.isCancelled { testState = .idle }
            case .failure(let error):
                if case .offline = error {
                    testState = .offline
                } else if case .endpointUnreachable = error {
                    testState = .invalid([error.errorDescription, error.recoverySuggestion]
                        .compactMap { $0 }.joined(separator: " "))
                } else {
                    // Never silently delete a key that failed — it may be a transient outage.
                    testState = .invalid(error.recoverySuggestion ?? error.errorDescription ?? "That key was rejected.")
                }
            }
        }
    }

    private var strokeColor: Color? {
        if case .invalid = testState { return Theme.Color.danger.opacity(0.5) }
        return nil
    }
}

// MARK: - Styles used only here

/// The 3-up default-provider tile (h56, r12).
private struct TileButtonStyle: ButtonStyle {
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

private struct TrashButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StyleBody(configuration: configuration)
    }

    private struct StyleBody: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering ? Theme.Color.danger : Theme.Color.textTertiary)
                .minimumHitTarget(24)
                .onHover { isHovering = $0 }
        }
    }
}

// MARK: - Previews

#Preview("Providers — configured") {
    ProvidersSettingsView(settings: .shared, router: SettingsRouter())
        .frame(width: 560, height: 620)
}
