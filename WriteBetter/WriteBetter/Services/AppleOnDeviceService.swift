import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether Apple's on-device model can run right now, without any of the Apple
/// Intelligence types leaking into code that must still load on macOS 14.
nonisolated enum AppleIntelligence {
    enum Availability: Equatable, Sendable {
        case available
        /// Plain-language reason, safe to show in Settings.
        case unavailable(String)
    }

    static var availability: Availability {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable("This Mac doesn't support Apple Intelligence.")
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable("Apple Intelligence is turned off. Turn it on in System Settings → Apple Intelligence & Siri.")
            case .unavailable(.modelNotReady):
                return .unavailable("The on-device model is still downloading. Try again in a few minutes.")
            case .unavailable:
                return .unavailable("The on-device model isn't available right now.")
            }
        }
        #endif
        return .unavailable("Needs macOS 26 or later with Apple Intelligence.")
    }

    static var isAvailable: Bool { availability == .available }

    /// The service, or `nil` on a macOS that can't host it.
    static func makeService() -> AIService? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleOnDeviceService() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
/// Apple's on-device foundation model (FoundationModels, macOS 26+). No key, no network.
///
/// `streamResponse` yields *cumulative* snapshots, not deltas; `Delta` turns them back
/// into the appended text the rest of the app expects. The context window is small
/// (about 4K tokens, prompt and answer together), so a long selection is refused with
/// a clear message rather than a generic failure.
@available(macOS 26.0, *)
nonisolated struct AppleOnDeviceService: AIService {
    let provider: AIProvider = .apple
    let modelID = AIProvider.apple.defaultModelID

    /// Turns cumulative snapshots into appended fragments.
    ///
    /// If a later snapshot rewrites text already emitted (not a pure extension), nothing
    /// can be un-sent, so the fragment is withheld and `diverged` is set; the caller then
    /// fails the request instead of leaving a corrupted rewrite on the clipboard.
    struct Delta {
        private(set) var emitted = ""
        private(set) var diverged = false

        mutating func next(_ snapshot: String) -> String? {
            guard snapshot.hasPrefix(emitted) else { diverged = true; return nil }
            let fragment = String(snapshot.dropFirst(emitted.count))
            guard !fragment.isEmpty else { return nil }
            emitted = snapshot
            return fragment
        }
    }

    func improveTextStream(request improvement: ImprovementRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !improvement.isEmpty else { throw AIServiceError.emptyInput }
                    if case .unavailable(let reason) = AppleIntelligence.availability {
                        throw AIServiceError.api(reason)
                    }

                    let session = LanguageModelSession(instructions: improvement.systemPrompt)
                    var delta = Delta()
                    for try await snapshot in session.streamResponse(to: improvement.userPrompt) {
                        try Task.checkCancellation()
                        if let fragment = delta.next(snapshot.content) { continuation.yield(fragment) }
                    }
                    if delta.diverged {
                        throw AIServiceError.api("The on-device model changed its answer mid-way. Try again.")
                    }
                    if delta.emitted.isEmpty {
                        throw AIServiceError.api("The on-device model returned no text. Try again.")
                    }
                    continuation.finish()
                } catch {
                    if HTTPStream.isCancellation(error) {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: Self.map(error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Nothing to authenticate: "valid" means the model is ready.
    func validateKey() async -> Result<Void, AIServiceError> {
        switch AppleIntelligence.availability {
        case .available: return .success(())
        case .unavailable(let reason): return .failure(.api(reason))
        }
    }

    static func map(_ error: Error) -> AIServiceError {
        if let serviceError = error as? AIServiceError { return serviceError }
        guard let generation = error as? LanguageModelSession.GenerationError else {
            return .api(error.localizedDescription)
        }
        switch generation {
        case .exceededContextWindowSize:
            return .api("Selection too long for the on-device model. Select less text, or pick another provider.")
        case .guardrailViolation, .refusal:
            return .api("Apple's on-device safety filter declined this text. Try different wording, or another provider.")
        case .assetsUnavailable:
            return .api("The on-device model isn't ready yet. Try again in a few minutes.")
        case .unsupportedLanguageOrLocale:
            return .api("The on-device model doesn't support this language yet. Pick another provider.")
        case .rateLimited, .concurrentRequests:
            return .rateLimited(retryAfter: nil)
        default:
            return .api("The on-device model couldn't complete this. Try again.")
        }
    }
}
#endif
