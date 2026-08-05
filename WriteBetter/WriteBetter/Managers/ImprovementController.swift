import AppKit
import Combine
import SwiftUI

/// The panel's state machine and the only place a stream is consumed.
///
/// Streaming performance is the reason this class exists rather than living in the
/// view (§11.2 pitfall 6): incoming chunks are **coalesced into 50 ms batches**
/// before touching `@Published`, which removes ~90% of SwiftUI's CoreText layout
/// passes and is invisible to the user against the 200–600 ms first-token budget.
@MainActor
final class ImprovementController: ObservableObject {

    // MARK: - Phases (§7.1)

    /// Eleven documented panel states collapse to nine phases; the four
    /// error-shaped ones (`error`, `offline`, `invalid-key`, `rate-limited`,
    /// `quota`) are distinguished by the associated `AIServiceError`.
    enum Phase {
        case idle
        case capturing
        case streaming
        case done
        case cancelled
        case emptyInput
        /// `noProviderConfigured` / `missingKey` — the Setup card.
        case needsKey(AIProvider)
        /// A key is being checked from the Setup card's inline field.
        case validating(AIProvider)
        case failed(AIServiceError)

        /// A stable discriminator, so views can animate on phase changes without
        /// depending on `AIServiceError` being `Equatable`.
        var kind: String {
            switch self {
            case .idle:            return "idle"
            case .capturing:       return "capturing"
            case .streaming:       return "streaming"
            case .done:            return "done"
            case .cancelled:       return "cancelled"
            case .emptyInput:      return "emptyInput"
            case .needsKey:        return "needsKey"
            case .validating:      return "validating"
            case .failed(let e):   return "failed.\(String(describing: e))"
            }
        }

        var isStreaming: Bool { if case .streaming = self { return true }; return false }
        var isCapturing: Bool { if case .capturing = self { return true }; return false }
        var isBusy: Bool { isStreaming || isCapturing }

        var error: AIServiceError? {
            if case .failed(let error) = self { return error }
            return nil
        }
    }

    // MARK: - Published state

    @Published private(set) var phase: Phase = .idle
    /// What the result canvas renders. Capped for display; `resultText` is complete.
    @Published private(set) var displayText: String = ""
    @Published private(set) var originalText: String = ""
    @Published private(set) var captureSource: TextExtractor.Source = .clipboard
    @Published private(set) var wasTruncated = false
    @Published private(set) var activeAction: QuickAction?
    @Published private(set) var retryCountdown: Int?
    @Published private(set) var lastOutcomeMessage: String?

    /// The custom-instruction field (C11).
    @Published var customPrompt: String = ""
    /// The inline key field on the Setup / invalid-key cards.
    @Published var inlineKeyDraft: String = ""
    @Published private(set) var inlineKeyError: String?

    // MARK: - Non-published

    /// The full result, never truncated — this is what Copy and Replace use.
    private(set) var resultText: String = ""

    private var buffer = ""
    private var flushScheduled = false
    private var streamTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var validationTask: Task<Void, Never>?

    private var lastRequestedAction: QuickAction?
    private var lastRequestedPrompt: String?

    private let settings: SettingsStore
    private let replaceService: ReplaceService

    /// 50 ms → 20 fps. See §11.2 pitfall 6.
    private static let flushInterval: Duration = .milliseconds(50)
    /// Display cap; the full string is kept for copying.
    private static let displayCap = 20_000

    // MARK: - Hooks the window owner installs

    var onClose: () -> Void = {}
    var onOpenSettings: (AIProvider?) -> Void = { _ in }
    var onAnnounce: (String) -> Void = { _ in }

    // MARK: - Init

    /// Defaults are resolved inside the body: a default *argument expression* is
    /// evaluated in a nonisolated context, which cannot touch `@MainActor` state.
    init(settings: SettingsStore? = nil, replaceService: ReplaceService? = nil) {
        self.settings = settings ?? .shared
        self.replaceService = replaceService ?? ReplaceService()
    }

    // MARK: - Derived values for the view

    var selectedProvider: AIProvider { settings.selectedProvider }

    var selectedModel: AIModelOption? {
        let id = settings.modelID(for: settings.selectedProvider)
        return settings.selectedProvider.models.first { $0.id == id }
    }

    var configuredProviders: [AIProvider] {
        AIProvider.allCases.filter { settings.configuredProviders.contains($0) }
    }

    var canCycleProviders: Bool { configuredProviders.count >= 2 }

    var canReplaceInPlace: Bool { replaceService.canReplace }

    var hasResult: Bool { !resultText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// `+14` / `−22`, or nil when there is nothing to compare yet.
    var wordDelta: Int? {
        switch phase {
        case .done, .cancelled:
            guard hasResult else { return nil }
            return Self.wordCount(resultText) - Self.wordCount(originalText)
        default:
            return nil
        }
    }

    var resultWordCount: Int { Self.wordCount(resultText) }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Lifecycle

    /// Seeds the panel with freshly captured text and kicks off the default run.
    func begin(capture: TextExtractor.Capture?) {
        originalText = capture?.text ?? ""
        captureSource = capture?.source ?? .clipboard
        wasTruncated = capture?.truncated ?? false
        customPrompt = ""
        inlineKeyDraft = ""
        inlineKeyError = nil
        lastOutcomeMessage = nil
        resetResult()

        // §9.4: fix the blocking problem first — no key beats no text.
        if !settings.isConfigured {
            phase = .needsKey(settings.selectedProvider)
            return
        }
        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .emptyInput
            return
        }
        run(action: nil, customPrompt: nil)
    }

    /// Seeds text without running anything — used by the Welcome window's live sample.
    func load(text: String) {
        originalText = text
        captureSource = .clipboard
        wasTruncated = false
        resetResult()
        phase = .idle
    }

    /// The empty-input state's "Try again" — re-reads the pasteboard.
    func retryCapture(using extractor: TextExtractor) {
        guard let text = extractor.clipboardText() else {
            phase = .emptyInput
            return
        }
        originalText = String(text.prefix(TextExtractor.maxCharacters))
        wasTruncated = text.count > TextExtractor.maxCharacters
        captureSource = .clipboard
        run(action: nil, customPrompt: nil)
    }

    func teardown() {
        streamTask?.cancel()
        countdownTask?.cancel()
        validationTask?.cancel()
        streamTask = nil
        countdownTask = nil
        validationTask = nil
    }

    // MARK: - Running

    func run(action: QuickAction?, customPrompt promptText: String?) {
        countdownTask?.cancel()
        retryCountdown = nil
        streamTask?.cancel()

        let trimmedPrompt = promptText?.trimmingCharacters(in: .whitespacesAndNewlines)
        lastRequestedAction = action
        lastRequestedPrompt = (trimmedPrompt?.isEmpty ?? true) ? nil : trimmedPrompt
        activeAction = action

        guard !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .emptyInput
            return
        }

        let service: AIService
        do {
            service = try AIServiceFactory.makeService()
        } catch let error as AIServiceError {
            resetResult()
            phase = Self.isKeyProblem(error) ? .needsKey(settings.selectedProvider) : .failed(error)
            return
        } catch {
            resetResult()
            phase = .failed(.invalidResponse)
            return
        }

        resetResult()
        phase = .capturing
        lastOutcomeMessage = nil

        let request = ImprovementRequest(originalText: originalText,
                                         action: action,
                                         customPrompt: lastRequestedPrompt)

        streamTask = Task { [weak self] in
            do {
                for try await chunk in service.improveTextStream(request: request) {
                    if Task.isCancelled { break }
                    guard let self else { return }
                    self.append(chunk)
                }
                guard let self, !Task.isCancelled else { return }
                self.finishStream()
            } catch is CancellationError {
                return
            } catch let error as AIServiceError {
                guard let self, !Task.isCancelled else { return }
                self.fail(with: error)
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.fail(with: .network(error.localizedDescription))
            }
        }
    }

    /// `⌘R` — re-run the last request unchanged (M14).
    func regenerate() {
        guard !phase.isCapturing else { return }
        run(action: lastRequestedAction, customPrompt: lastRequestedPrompt)
    }

    /// `esc` while streaming — keeps whatever has arrived.
    func stop() {
        guard phase.isBusy else { return }
        streamTask?.cancel()
        streamTask = nil
        flushNow()
        phase = .cancelled
        onAnnounce("Stopped.")
    }

    // MARK: - Streaming internals

    private func append(_ chunk: String) {
        buffer += chunk
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: Self.flushInterval)
            self?.flushNow()
        }
    }

    private func flushNow() {
        flushScheduled = false
        guard !buffer.isEmpty else { return }

        resultText += buffer
        buffer = ""

        // One `Text`, one string, capped for display (§11.2 pitfall 6).
        displayText = resultText.count > Self.displayCap
            ? String(resultText.suffix(Self.displayCap))
            : resultText

        if phase.isCapturing {
            phase = .streaming
        }
    }

    private func finishStream() {
        flushNow()
        streamTask = nil
        phase = .done
        onAnnounce("Done. \(resultWordCount) words.")
    }

    private func fail(with error: AIServiceError) {
        flushNow()
        streamTask = nil

        if Self.isKeyProblem(error) {
            inlineKeyDraft = ""
            inlineKeyError = nil
            phase = Self.isInvalidKey(error) ? .failed(error) : .needsKey(settings.selectedProvider)
        } else {
            phase = .failed(error)
        }

        if case .rateLimited(let retryAfter) = error, let seconds = retryAfter, seconds > 0 {
            startCountdown(seconds: Int(seconds.rounded()))
        }
    }

    private func resetResult() {
        streamTask?.cancel()
        streamTask = nil
        buffer = ""
        flushScheduled = false
        resultText = ""
        displayText = ""
    }

    // MARK: - Rate-limit countdown (§7.1 rate-limited state)

    private func startCountdown(seconds: Int) {
        retryCountdown = seconds
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                guard let self else { return }
                self.retryCountdown = remaining
            }
            guard let self, !Task.isCancelled else { return }
            self.retryCountdown = nil
            self.regenerate()
        }
    }

    // MARK: - Provider switching (§8)

    func select(provider: AIProvider) {
        guard settings.configuredProviders.contains(provider) else {
            // Unconfigured: never silently change the default. Send them to Settings.
            onOpenSettings(provider)
            return
        }
        guard provider != settings.selectedProvider else { return }
        settings.selectedProvider = provider
        streamTask?.cancel()
        regenerate()
    }

    /// `⌘]` / `⌘[` — wrap through configured providers in `allCases` order.
    func cycleProvider(forward: Bool) {
        let pool = configuredProviders
        guard pool.count >= 2 else { return }
        let current = settings.selectedProvider
        let index = pool.firstIndex(of: current) ?? 0
        let next = forward
            ? pool[(index + 1) % pool.count]
            : pool[(index - 1 + pool.count) % pool.count]
        select(provider: next)
    }

    // MARK: - Inline key entry (Setup card / invalid-key card)

    var inlineKeyProvider: AIProvider {
        switch phase {
        case .needsKey(let provider), .validating(let provider):
            return provider
        case .failed(.invalidKey(let provider)):
            return provider
        default:
            return settings.selectedProvider
        }
    }

    /// Validates, saves, then immediately runs the improvement (§7.1 Setup card).
    func submitInlineKey() {
        let provider = inlineKeyProvider
        let key = inlineKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        inlineKeyError = nil
        phase = .validating(provider)

        validationTask?.cancel()
        validationTask = Task { [weak self] in
            guard let self else { return }
            let modelID = self.settings.modelID(for: provider)
            let service = AIServiceFactory.service(for: provider, apiKey: key, modelID: modelID)
            let result = await service.validateKey()
            if Task.isCancelled { return }

            switch result {
            case .success:
                self.settings.setAPIKey(key, for: provider)
                self.settings.selectedProvider = provider
                self.inlineKeyDraft = ""
                if self.originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.phase = .emptyInput
                } else {
                    self.run(action: self.lastRequestedAction, customPrompt: self.lastRequestedPrompt)
                }
            case .failure(let error):
                self.inlineKeyError = error.recoverySuggestion ?? error.errorDescription
                self.phase = .needsKey(provider)
            }
        }
    }

    /// The Setup card's 3-up tile row.
    func chooseSetupProvider(_ provider: AIProvider) {
        inlineKeyError = nil
        inlineKeyDraft = ""
        if settings.configuredProviders.contains(provider) {
            settings.selectedProvider = provider
            regenerate()
        } else {
            phase = .needsKey(provider)
        }
    }

    // MARK: - Output

    /// `↩` (close) and `⇧↩` (stay open).
    func copyResult(closeAfter: Bool) {
        guard hasResult else { return }
        replaceService.copyToClipboard(resultText)
        lastOutcomeMessage = "Copied to clipboard"
        onAnnounce("Copied.")
        if closeAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onClose()
            }
        }
    }

    /// `⌘↩` — paste back into the source app, or fall back to the clipboard and
    /// say which one happened.
    func replaceInPlace() {
        guard hasResult else { return }
        let outcome = replaceService.replace(resultText) { [weak self] in
            self?.onClose()
        }
        switch outcome {
        case .replaced(let appName):
            onAnnounce("Replaced in \(appName).")
        case .copiedToClipboard:
            lastOutcomeMessage = "Copied — paste it with ⌘V"
            onAnnounce("Copied to the clipboard. Paste it with Command V.")
        }
    }

    // MARK: - Error classification

    private static func isKeyProblem(_ error: AIServiceError) -> Bool {
        switch error {
        case .noProviderConfigured, .missingKey, .invalidKey: return true
        default: return false
        }
    }

    private static func isInvalidKey(_ error: AIServiceError) -> Bool {
        if case .invalidKey = error { return true }
        return false
    }
}

// MARK: - Preview support

extension ImprovementController {
    /// Builds a controller parked in a given phase, with no services and no network,
    /// so every `#Preview` renders (§11.2 pitfall 13).
    static func preview(phase: Phase,
                        original: String = "this is a test text that needs improvement and should be made better, i wrote it fast and it shows",
                        result: String = "",
                        action: QuickAction? = nil) -> ImprovementController {
        let controller = ImprovementController()
        controller.originalText = original
        controller.resultText = result
        controller.displayText = result
        controller.activeAction = action
        controller.phase = phase
        return controller
    }
}
