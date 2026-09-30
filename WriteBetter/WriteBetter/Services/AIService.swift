import Foundation

/// One configured provider + model, ready to stream a rewrite.
nonisolated protocol AIService: Sendable {
    var provider: AIProvider { get }
    var modelID: String { get }

    /// Streams the rewritten text in order. Cancelling the consuming `Task`
    /// tears down the underlying URLSession task.
    func improveTextStream(request: ImprovementRequest) -> AsyncThrowingStream<String, Error>

    /// Cheap auth check used by Settings' "Test key" button. Costs no tokens.
    func validateKey() async -> Result<Void, AIServiceError>
}

/// Everything that can go wrong, mapped from real HTTP status codes and provider
/// error payloads. The UI renders `errorDescription` with `recoverySuggestion`
/// underneath it.
nonisolated enum AIServiceError: LocalizedError, Sendable, Equatable {
    /// No provider has a key at all.
    case noProviderConfigured
    /// The selected provider has no key.
    case missingKey(AIProvider)
    /// 401/403 — the key was rejected.
    case invalidKey(AIProvider)
    /// 429 — too many requests. `retryAfter` is seconds, when the provider said.
    case rateLimited(retryAfter: TimeInterval?)
    /// Billing or credit exhausted.
    case quotaExceeded
    /// 5xx (including Anthropic's 529 overloaded).
    case serverError(Int)
    /// No first byte within `Constants.firstByteTimeout`, or the whole request
    /// exceeded `Constants.overallTimeout`.
    case timedOut
    /// The machine is not on the internet.
    case offline
    /// Any other transport failure.
    case network(String)
    /// The provider returned a structured error we surface verbatim.
    case api(String)
    /// The body did not look like what the provider documents.
    case invalidResponse
    /// Nothing was selected.
    case emptyInput
    /// The custom endpoint could not be reached. `localNetworkBlocked` means macOS's
    /// Local Network privacy switch is the reason, not the server.
    case endpointUnreachable(host: String, localNetworkBlocked: Bool)

    var errorDescription: String? {
        switch self {
        case .noProviderConfigured:
            return "WriteBetter isn't set up yet."
        case .missingKey(let provider):
            if !provider.needsAPIKey { return "No server address saved for \(provider.displayName)." }
            return "No \(provider.displayName) API key saved."
        case .invalidKey(let provider):
            return "\(provider.displayName) rejected this API key."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter, seconds > 0 {
                return "Rate limited — too many requests (retry in \(Int(seconds.rounded()))s)."
            }
            return "Rate limited — too many requests."
        case .quotaExceeded:
            return "Your account is out of credit."
        case .serverError(let code):
            return "The provider had a problem (HTTP \(code))."
        case .timedOut:
            return "The request timed out."
        case .offline:
            return "You're offline."
        case .network(let detail):
            return "Network problem: \(detail)"
        case .api(let message):
            return message
        case .invalidResponse:
            return "The provider sent a response WriteBetter couldn't read."
        case .emptyInput:
            return "There's no text to improve."
        case .endpointUnreachable(let host, let blocked):
            return blocked
                ? "macOS blocked WriteBetter from reaching \(host)."
                : "Couldn't connect to \(host)."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noProviderConfigured:
            return "Open Settings and add an API key for Anthropic, OpenAI or Google Gemini, or point WriteBetter at a local server."
        case .missingKey(let provider):
            if !provider.needsAPIKey { return "Open Settings and enter the server's base URL." }
            return "Open Settings and paste your \(provider.displayName) key."
        case .invalidKey(let provider):
            if let prefix = provider.keyPrefixHint {
                return "Check the key in Settings — \(provider.displayName) keys start with \(prefix)."
            }
            return "Check the key in Settings, or create a new one in the \(provider.displayName) console."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter, seconds > 0 {
                return "Wait about \(Int(seconds.rounded())) seconds and try again."
            }
            return "Wait a few seconds and try again."
        case .quotaExceeded:
            return "Add credit or raise your spending limit in the provider's console."
        case .serverError:
            return "That's on their side — try again in a moment."
        case .timedOut:
            return "Check your connection, or try again with a shorter selection."
        case .offline:
            return "Reconnect to the internet and try again."
        case .network:
            return "Check your connection and try again."
        case .api:
            return "Try again, or switch model in Settings."
        case .invalidResponse:
            return "Try again. If it keeps happening, switch model in Settings."
        case .emptyInput:
            return "Select some text first, then press the hotkey."
        case .endpointUnreachable(_, let blocked):
            return blocked
                ? "Allow WriteBetter in System Settings → Privacy & Security → Local Network, then try again."
                : "Check that the server is running and that the address in Settings is right."
        }
    }
}
