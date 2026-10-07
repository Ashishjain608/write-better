import AppKit
import SwiftUI

/// The floating improvement panel (§7.1) — every state, every key.
struct ImprovementView: View {

    @ObservedObject var controller: ImprovementController
    @ObservedObject var router: PanelKeyRouter
    @ObservedObject var settings: SettingsStore
    @ObservedObject var customActions: CustomActionStore
    let extractor: TextExtractor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var sourceExpanded = false
    @State private var showHelp = false
    @State private var showPermissionExplainer = false
    /// The instruction being saved as a custom action (the "Save as action" sheet).
    @State private var savingInstruction: String?
    /// The saved action that produced the current result; the controller only
    /// tracks built-ins, so the panel tracks this one itself.
    @State private var activeCustomID: CustomAction.ID?
    @State private var confirmation: String?
    @State private var copyPulse = false
    @State private var rimPeak = false
    @FocusState private var promptFocused: Bool

    init(controller: ImprovementController,
         router: PanelKeyRouter,
         extractor: TextExtractor,
         settings: SettingsStore,
         customActions: CustomActionStore? = nil) {
        self.controller = controller
        self.router = router
        self.extractor = extractor
        self.settings = settings
        self.customActions = customActions ?? MainActor.assumeIsolated { .shared }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 560)
        .frame(minHeight: 300, maxHeight: 620, alignment: .top)
        .glassSurface(cornerRadius: Theme.Radius.panel,
                      rimAccent: rimAccent,
                      rimTint: Theme.Color.streaming)
        .overlay { if showHelp { ShortcutsOverlay(isPresented: $showHelp) } }
        .overlay { if showPermissionExplainer { permissionExplainer } }
        .overlay {
            if let savingInstruction {
                SaveActionSheet(instruction: savingInstruction,
                                store: customActions,
                                onDismiss: { self.savingInstruction = nil },
                                onSaved: { digit in show(confirmation: "Saved as ⌘\(digit)") })
            }
        }
        .onReceive(router.commands, perform: handle)
        .onChange(of: controller.phase.kind) { _, _ in phaseChanged() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("WriteBetter")
    }

    // MARK: - C1 Header rail

    private var header: some View {
        HStack(spacing: Theme.Space.md) {
            BrandMark(size: 18)
            Text("WriteBetter")
                .textStyle(.label)
                .foregroundStyle(Theme.Color.textPrimary.opacity(0.85))

            Spacer(minLength: Theme.Space.lg)

            providerChip
            closeButton
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 44)
        // The whole rail drags the window (no visible divider — the 12pt gap separates).
        .contentShape(Rectangle())
    }

    // MARK: - C3 Provider chip + menu (§8.1)

    private var providerChip: some View {
        Menu {
            providerMenu
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Circle()
                    .fill(chipDotColor)
                    .frame(width: 8, height: 8)
                if settings.configuredProviders.isEmpty {
                    Text("Choose a provider").textStyle(.label).lineLimit(1)
                } else {
                    Text(settings.selectedProvider.displayName)
                        .textStyle(.label)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Text("·").textStyle(.caption)
                    Text(controller.selectedModel?.name ?? "")
                        .textStyle(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.Color.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, Theme.Space.md)
            .frame(maxWidth: 220)
            .cardSurface(radius: Theme.Radius.chip)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .animation(Theme.Motion.curve(.easeInOut(duration: 0.24), reduceMotion: reduceMotion),
                   value: settings.selectedProvider)
        .help("Switch provider")
        .accessibilityLabel("Provider")
        .accessibilityValue("\(settings.selectedProvider.displayName), \(controller.selectedModel?.name ?? "no model")")
        .accessibilityHint("Opens the provider menu")
    }

    private var chipDotColor: Color {
        switch controller.phase {
        case .failed(.invalidKey):                      return Theme.Color.danger
        case .failed(.rateLimited), .failed(.quotaExceeded): return Theme.Color.warning
        case .needsKey, .validating:                    return Theme.Color.warning
        default:
            return settings.configuredProviders.isEmpty
                ? Theme.Color.warning
                : settings.selectedProvider.accent
        }
    }

    @ViewBuilder
    private var providerMenu: some View {
        ForEach(AIProvider.allCases) { provider in
            Button {
                controller.select(provider: provider)
            } label: {
                if settings.configuredProviders.contains(provider) {
                    Text(provider == settings.selectedProvider
                         ? "✓ \(provider.displayName)"
                         : "   \(provider.displayName)")
                } else {
                    Text("   \(provider.displayName) — Add key…")
                }
            }
        }
        Divider()
        Button("Change model…") {
            SettingsRouter.shared.open(provider: settings.selectedProvider)
        }
        .keyboardShortcut("m", modifiers: .command)
        Button("Settings…") {
            SettingsRouter.shared.open()
        }
        .keyboardShortcut(",", modifiers: .command)
    }

    // MARK: - C4 Close

    private var closeButton: some View {
        Button {
            controller.onClose()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(IconButtonStyle())
        .help("Close (esc)")
        .accessibilityLabel("Close")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            switch controller.phase {
            case .emptyInput:
                EmptyInputCard()
            default:
                if showsSource { sourceBlock }
                resultBlock
            }

            if showsQuickActions {
                quickActionRail
                if !customActions.actions.isEmpty { customActionRail }
            }
            if showsPromptBar { promptBar }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.xs)
        .animation(Theme.Motion.curve(Theme.Motion.enter, reduceMotion: reduceMotion),
                   value: controller.phase.kind)
    }

    // MARK: Source block (C5 + C6)

    private var sourceBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Original") {
                HStack(spacing: Theme.Space.md) {
                    Text("\(controller.originalText.count) chars")
                        .textStyle(.caption)
                        .monospacedDigit()
                    Button {
                        withAnimation(Theme.Motion.curve(Theme.Motion.standard, reduceMotion: reduceMotion)) {
                            sourceExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: sourceExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .minimumHitTarget(20)
                    .help(sourceExpanded ? "Collapse original" : "Expand original")
                    .accessibilityLabel(sourceExpanded ? "Collapse original" : "Expand original")
                }
            }
            SourceStrip(text: controller.originalText,
                        truncated: controller.wasTruncated,
                        isExpanded: sourceExpanded)
        }
    }

    // MARK: Result block (C5 + C7 / cards)

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: resultHeaderTitle) {
                HStack(spacing: Theme.Space.md) {
                    statusBadge
                    if let delta = controller.wordDelta, delta != 0 {
                        Text(delta > 0 ? "+\(delta) wds" : "\(delta) wds")
                            .textStyle(.caption)
                            .monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                    }
                }
            }
            resultSurface
            if case .cancelled = controller.phase, let error = controller.cutOffError {
                CutOffNotice(error: error)
            } else if case .done = controller.phase, controller.wasTruncated {
                Label(controller.replaceabilityBlocker ?? "Only the first 20,000 characters were rewritten.",
                      systemImage: "exclamationmark.circle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.warning)
            }
        }
    }

    private var resultHeaderTitle: String {
        switch controller.phase {
        case .needsKey, .validating: return "Set up"
        case .failed(.invalidKey):   return "Set up"
        default:                     return "Improved"
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch controller.phase {
        case .streaming, .capturing:
            StatusPill(text: "Streaming", tint: Theme.Color.streaming, showsDot: true)
        case .cancelled:
            StatusPill(text: controller.wasCutOff ? "Cut off" : "Stopped", tint: Theme.Color.warning,
                       systemImage: "exclamationmark.circle.fill")
        case .validating:
            StatusPill(text: "Checking", tint: Theme.Color.accent, showsDot: true)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var resultSurface: some View {
        switch controller.phase {
        case .capturing where controller.displayText.isEmpty:
            SkeletonLines()
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
                .sunkenSurface()

        case .needsKey(let provider), .validating(let provider):
            SetupCard(providers: AIProvider.allCases,
                      selected: provider,
                      configured: settings.configuredProviders,
                      key: $controller.inlineKeyDraft,
                      isValidating: isValidating,
                      errorText: controller.inlineKeyError,
                      onSelect: controller.chooseSetupProvider,
                      onSubmit: controller.submitInlineKey)

        case .failed(let error):
            errorSurface(for: error)

        default:
            ResultCanvas(text: controller.displayText,
                         isStreaming: controller.phase.isStreaming,
                         strokeTint: canvasStroke)
        }
    }

    private var isValidating: Bool {
        if case .validating = controller.phase { return true }
        return false
    }

    private var canvasStroke: Color? {
        switch controller.phase {
        case .streaming, .capturing: return Theme.Color.streaming.opacity(0.35)
        case .cancelled:             return Theme.Color.warning.opacity(0.30)
        default:                     return nil
        }
    }

    /// Every error-shaped state (§7.1): generic error, offline, invalid key,
    /// rate-limited and quota, each with its own glyph, tint and extra affordance.
    @ViewBuilder
    private func errorSurface(for error: AIServiceError) -> some View {
        switch error {
        case .offline:
            ErrorCard(symbol: "wifi.slash",
                      tint: Theme.Color.danger,
                      title: error.errorDescription ?? "You're offline.",
                      suggestion: "Reconnect and press ⌘R.")

        case .invalidKey(let provider):
            ErrorCard(symbol: "key.fill",
                      tint: Theme.Color.danger,
                      title: error.errorDescription ?? "That key was rejected.",
                      suggestion: error.recoverySuggestion) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    InlineKeyField(provider: provider,
                                   key: $controller.inlineKeyDraft,
                                   isValidating: isValidating,
                                   onSubmit: controller.submitInlineKey)
                    ConsoleLink(provider: provider)
                }
            }

        case .rateLimited:
            ErrorCard(symbol: "hourglass",
                      tint: Theme.Color.warning,
                      title: error.errorDescription ?? "Rate limited.",
                      suggestion: error.recoverySuggestion,
                      countdown: controller.retryCountdown)

        case .quotaExceeded:
            ErrorCard(symbol: "creditcard.fill",
                      tint: Theme.Color.warning,
                      title: error.errorDescription ?? "Out of credit.",
                      suggestion: error.recoverySuggestion) {
                Button {
                    NSWorkspace.shared.open(settings.selectedProvider.consoleURL)
                } label: {
                    Label("Open billing", systemImage: "arrow.up.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

        default:
            ErrorCard(symbol: "exclamationmark.triangle.fill",
                      tint: Theme.Color.danger,
                      title: error.errorDescription ?? "Something went wrong.",
                      suggestion: error.recoverySuggestion)
        }
    }

    // MARK: - C10 Quick-action rail

    private var quickActionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.md) {
                ForEach(Array(QuickAction.allCases.enumerated()), id: \.element.id) { index, action in
                    Button {
                        promptFocused = false
                        activeCustomID = nil
                        controller.run(action: action, customPrompt: nil)
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: action.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(action.title).lineLimit(1)
                            if router.isCommandHeld, index < 9 {
                                Text("\(index + 1)")
                                    .textStyle(.keycap)
                                    .foregroundStyle(Theme.Color.accentText)
                            }
                        }
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: controller.activeAction == action))
                    .disabled(!quickActionsEnabled)
                    .help(action.title)
                    .accessibilityLabel(action.title)
                    .accessibilityHint("Rewrites the text. Command \(index + 1)")
                }
            }
            .padding(.horizontal, Theme.Space.xl)
        }
        .frame(height: 34)
        .padding(.horizontal, -Theme.Space.xl)
        .mask(edgeFade)
        .opacity(quickActionOpacity)
        .animation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion),
                   value: quickActionOpacity)
    }

    /// Second row: saved actions on ⌘6–⌘9, same chips as the built-ins. A row of
    /// its own keeps the built-in row untouched; a scroll covers long names.
    private var customActionRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.md) {
                ForEach(Array(customActions.actions.enumerated()), id: \.element.id) { index, action in
                    let digit = CustomAction.shortcutDigit(at: index)
                    Button {
                        run(custom: action)
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            if let icon = action.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(action.name).lineLimit(1)
                            if router.isCommandHeld, let digit {
                                Text("\(digit)")
                                    .textStyle(.keycap)
                                    .foregroundStyle(Theme.Color.accentText)
                            }
                        }
                    }
                    .buttonStyle(ChipButtonStyle(isSelected: activeCustomID == action.id && controller.activeAction == nil))
                    .disabled(!quickActionsEnabled)
                    .help(action.instruction)
                    .accessibilityLabel(action.name)
                    .accessibilityHint(digit.map { "Runs your saved action. Command \($0)" } ?? "Runs your saved action")
                }
            }
            .padding(.horizontal, Theme.Space.xl)
        }
        .frame(height: 34)
        .padding(.horizontal, -Theme.Space.xl)
        .mask(edgeFade)
        .opacity(quickActionOpacity)
        .animation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion),
                   value: quickActionOpacity)
    }

    private func run(custom action: CustomAction) {
        promptFocused = false
        controller.run(action: nil, customPrompt: action.instruction)
        activeCustomID = action.id
    }

    /// 16pt fade-out at both scroll edges.
    private var edgeFade: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.035),
            .init(color: .black, location: 0.965),
            .init(color: .clear, location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - C11 Prompt bar

    private var promptBar: some View {
        HStack(spacing: Theme.Space.md) {
            if !promptFocused {
                Keycap(symbol: "⌘K")
            }
            TextField("Tell it what to change…", text: $controller.customPrompt)
                .textFieldStyle(.plain)
                .textStyle(.body)
                .foregroundStyle(Theme.Color.textPrimary)
                .focused($promptFocused)
                .onSubmit(submitPrompt)

            if !controller.customPrompt.isEmpty {
                Button {
                    savingInstruction = controller.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                } label: {
                    Image(systemName: "bookmark")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .help("Save as action")
                .accessibilityLabel("Save as action")
                Keycap(symbol: "⌘↩")
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.Color.accent)
                }
                .buttonStyle(.plain)
                .minimumHitTarget()
                .help("Run this instruction (⌘↩)")
                .accessibilityLabel("Run this instruction")
            }
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(height: 38)
        .sunkenSurface(radius: Theme.Radius.control,
                       stroke: promptFocused ? Theme.Color.accent : nil,
                       lineWidth: promptFocused ? 1.5 : 1)
        .animation(Theme.Motion.curve(.easeOut(duration: 0.10), reduceMotion: reduceMotion),
                   value: promptFocused)
        .disabled(!promptEnabled)
        .opacity(promptEnabled ? 1 : 0.5)
        .accessibilityLabel("Custom instruction")
    }

    private func submitPrompt() {
        let text = controller.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        activeCustomID = nil
        controller.run(action: nil, customPrompt: text)
        controller.customPrompt = ""
        promptFocused = false
    }

    // MARK: - C12 Footer rail

    private var footer: some View {
        HStack(spacing: Theme.Space.lg) {
            if let confirmation {
                Label(confirmation, systemImage: "checkmark.circle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.success)
                    .transition(.opacity)
            } else {
                HStack(spacing: Theme.Space.lg) {
                    ForEach(Array(footerHints.enumerated()), id: \.offset) { _, hint in
                        KeyHint(key: hint.0, label: hint.1)
                    }
                }
            }

            Spacer(minLength: Theme.Space.lg)

            footerButtons
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(height: 48)
        .background(Theme.Color.railWash)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.stroke(reduceTransparency: reduceTransparency))
                .frame(height: 1)
        }
        .animation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion),
                   value: confirmation)
    }

    /// The `esc …` hint group, per state (§7.1 states table).
    private var footerHints: [(String, String)] {
        var hints: [(String, String)] = []
        switch controller.phase {
        case .capturing:
            hints = [("esc", "cancel")]
        case .streaming:
            hints = [("esc", "stop"), ("⌘R", "redo"), ("⌘,", "settings")]
        case .done:
            hints = [("esc", "close"), ("↩", "copy")]
            if controller.canReplaceInPlace { hints.append(("⌘↩", "replace")) }
            hints.append(("⌘R", "redo"))
        case .cancelled:
            hints = [("esc", "close"), ("↩", "copy"), ("⌘R", "redo")]
        case .emptyInput:
            hints = [("esc", "close")]
        case .needsKey, .validating:
            hints = [("esc", "close"), ("⌘,", "settings")]
        case .failed(let error):
            switch error {
            case .invalidKey:      hints = [("esc", "close"), ("⌘,", "settings")]
            case .quotaExceeded:
                hints = [("esc", "close")]
                if controller.canCycleProviders { hints.append(("⌘]", "next provider")) }
            case .rateLimited:     hints = [("esc", "close")]
            default:               hints = [("esc", "close"), ("⌘R", "retry")]
            }
        case .idle:
            hints = [("esc", "close"), ("?", "keys")]
        }
        return hints
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch controller.phase {
        case .capturing:
            stopButton

        case .streaming:
            HStack(spacing: Theme.Space.md) {
                stopButton
                Button("Copy") { copy(closeAfter: false) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!controller.hasResult)
                    .help("Copy what has arrived so far")
            }

        case .done:
            HStack(spacing: Theme.Space.md) {
                Button(replaceTitle) { replace() }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(!controller.isResultReplaceable)
                    .help(controller.canReplaceInPlace
                          ? "Paste back into the app you came from (⌘↩)"
                          : "Needs Accessibility access")
                Button("Copy") { copy(closeAfter: true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!controller.hasResult)
                    .scaleEffect(copyPulse ? 1.04 : 1.0)
                    .help("Copy and close (↩)")
            }

        case .cancelled:
            HStack(spacing: Theme.Space.md) {
                Button("Redo") { controller.regenerate() }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Copy") { copy(closeAfter: true) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!controller.hasResult)
            }

        case .emptyInput:
            Button("Try again") { controller.retryCapture(using: extractor) }
                .buttonStyle(PrimaryButtonStyle())
                .help("Re-read the clipboard")

        case .needsKey, .validating:
            Button(isValidating ? "Checking…" : "Save & run") { controller.submitInlineKey() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(controller.inlineKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || isValidating)

        case .failed(let error):
            failureButtons(for: error)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func failureButtons(for error: AIServiceError) -> some View {
        switch error {
        case .invalidKey:
            Button("Save & retry") { controller.submitInlineKey() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(controller.inlineKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        case .rateLimited:
            Button("Retry now") { controller.regenerate() }
                .buttonStyle(PrimaryButtonStyle())

        case .quotaExceeded:
            if controller.canCycleProviders {
                Button("Switch provider") { controller.cycleProvider(forward: true) }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button {
                    NSWorkspace.shared.open(settings.selectedProvider.consoleURL)
                } label: {
                    Label("Open billing", systemImage: "arrow.up.right")
                }
                .buttonStyle(PrimaryButtonStyle())
            }

        default:
            Button("Retry") { controller.regenerate() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var stopButton: some View {
        Button {
            controller.stop()
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .buttonStyle(SecondaryButtonStyle())
        .help("Stop generating (esc)")
        .accessibilityLabel("Stop")
    }

    private var replaceTitle: String {
        controller.canReplaceInPlace ? "Replace" : "Replace…"
    }

    // MARK: - Permission explainer (§9.3 rule 2)

    private var permissionExplainer: some View {
        ZStack {
            Theme.Color.scrim
                .onTapGesture { showPermissionExplainer = false }
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                Label("Replace text in place", systemImage: "text.insert")
                    .textStyle(.title)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("""
                     WriteBetter needs Accessibility access to read your current \
                     selection and paste the improved text back. Without it, copy \
                     with ⌘C first and paste with ⌘V after — everything else works \
                     exactly the same.
                     """)
                    .textStyle(.body)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Space.md) {
                    Button("Not now") { showPermissionExplainer = false }
                        .buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Open System Settings") {
                        AccessibilityManager.shared.openSystemSettings()
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    Button("Enable…") {
                        AccessibilityManager.shared.requestAccess()
                        showPermissionExplainer = false
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Theme.Space.xxl)
            .frame(width: 440)
            .raisedSurface(radius: Theme.Radius.panel)
        }
        .transition(.opacity)
    }

    // MARK: - Visibility rules (§7.1 states table)

    private var showsSource: Bool {
        switch controller.phase {
        case .needsKey, .validating: return false
        case .failed(.invalidKey), .failed(.quotaExceeded): return false
        default: return true
        }
    }

    private var showsQuickActions: Bool {
        switch controller.phase {
        case .emptyInput, .needsKey, .validating: return false
        case .failed(.invalidKey), .failed(.quotaExceeded): return false
        default: return true
        }
    }

    private var showsPromptBar: Bool { showsQuickActions }

    private var quickActionsEnabled: Bool {
        switch controller.phase {
        case .failed(.offline): return false
        default: return true
        }
    }

    private var quickActionOpacity: Double {
        switch controller.phase {
        case .capturing, .streaming:        return 0.6
        case .failed(.offline):             return 0.5
        case .failed(.rateLimited):         return 0.6
        default:                            return 1.0
        }
    }

    private var promptEnabled: Bool {
        switch controller.phase {
        case .failed(.offline): return false
        default: return true
        }
    }

    /// M7 — the panel rim breathes while streaming; static at 0.32 when motion or
    /// transparency is reduced.
    private var rimAccent: Double {
        guard controller.phase.isStreaming || controller.phase.isCapturing else { return 0 }
        if reduceMotion || reduceTransparency { return 0.32 }
        return rimPeak ? 0.45 : 0.20
    }

    // MARK: - Commands

    private func handle(_ command: PanelCommand) {
        switch command {
        case .escape:
            if controller.phase.isBusy {
                controller.stop()
            } else if showHelp {
                showHelp = false
            } else if showPermissionExplainer {
                showPermissionExplainer = false
            } else {
                controller.onClose()
            }

        case .copyAndClose:
            copy(closeAfter: true)

        case .copyStay:
            copy(closeAfter: false)

        case .replace:
            replace()

        case .regenerate:
            controller.regenerate()

        case .focusPrompt:
            guard showsPromptBar else { return }
            promptFocused = true

        case .clearPrompt:
            controller.customPrompt = ""

        case .quickAction(let index):
            let actions = QuickAction.allCases
            guard index >= 0, !controller.phase.isCapturing else { return }
            if index < actions.count {
                activeCustomID = nil
                controller.run(action: actions[index], customPrompt: nil)
            } else if customActions.actions.indices.contains(index - actions.count) {
                run(custom: customActions.actions[index - actions.count])
            }

        case .nextProvider:
            controller.cycleProvider(forward: true)

        case .previousProvider:
            controller.cycleProvider(forward: false)

        case .openSettings:
            SettingsRouter.shared.open()

        case .toggleHelp:
            withAnimation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                showHelp.toggle()
            }
        }
    }

    private func copy(closeAfter: Bool) {
        guard controller.hasResult else { return }
        controller.copyResult(closeAfter: closeAfter)
        show(confirmation: "Copied")
        guard !reduceMotion else { return }
        // M10 — one pulse, then back.
        withAnimation(Theme.Motion.celebrate) { copyPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(Theme.Motion.celebrate) { copyPulse = false }
        }
    }

    private func replace() {
        guard controller.hasResult else { return }
        if controller.replaceabilityBlocker != nil {
            controller.replaceInPlace() // announces the blocker
            return
        }
        guard controller.canReplaceInPlace else {
            withAnimation(Theme.Motion.curve(Theme.Motion.quick, reduceMotion: reduceMotion)) {
                showPermissionExplainer = true
            }
            return
        }
        controller.replaceInPlace()
    }

    private func show(confirmation text: String) {
        confirmation = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if confirmation == text { confirmation = nil }
        }
    }

    /// Starts/stops the streaming rim pulse when the phase changes, and surfaces the
    /// controller's own outcome messages (e.g. "Copied — paste it with ⌘V").
    private func phaseChanged() {
        let streaming = controller.phase.isStreaming || controller.phase.isCapturing
        if streaming, !reduceMotion, !reduceTransparency {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                rimPeak = true
            }
        } else {
            withAnimation(.linear(duration: 0.001)) { rimPeak = false }
        }
        if let message = controller.lastOutcomeMessage {
            show(confirmation: message)
        }
    }
}

// MARK: - Previews

@MainActor
private func previewPanel(_ controller: ImprovementController) -> some View {
    ImprovementView(controller: controller,
                    router: PanelKeyRouter(),
                    extractor: TextExtractor(),
                    settings: .shared)
        .background(Theme.Color.bgBase)
}

#Preview("Panel — streaming") {
    previewPanel(.preview(
        phase: .streaming,
        result: "This is a test passage that needs improvement and should be made better. I wrote it quickly, and it shows."
    ))
}

#Preview("Panel — done") {
    previewPanel(.preview(
        phase: .done,
        result: "This is a test passage that needed improvement, so I made it better. I wrote the first version quickly, and it showed.",
        action: .clarify
    ))
}

#Preview("Panel — error") {
    previewPanel(.preview(phase: .failed(.offline)))
}

#Preview("Panel — no API key") {
    previewPanel(.preview(phase: .needsKey(.anthropic)))
}

#Preview("Panel — rate limited") {
    previewPanel(.preview(phase: .failed(.rateLimited(retryAfter: 14)),
                          result: "Partial text that arrived before the limit hit."))
}

#Preview("Panel — empty input") {
    previewPanel(.preview(phase: .emptyInput, original: ""))
}

#Preview("Panel — cancelled") {
    previewPanel(.preview(phase: .cancelled,
                          result: "This is a test passage that needs improve"))
}
