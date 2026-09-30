import Foundation

/// Anthropic Messages API.
///
/// Wire reference: `POST https://api.anthropic.com/v1/messages` with headers
/// `x-api-key`, `anthropic-version: 2023-06-01`, `content-type: application/json`.
/// SSE events are `message_start`, `content_block_start`, `content_block_delta`
/// (text lives in `delta.text` of a `text_delta`), `content_block_stop`,
/// `message_delta`, `message_stop`, plus `ping` keep-alives and `error` events.
nonisolated struct AnthropicService: AIService {
    let provider: AIProvider = .anthropic
    let modelID: String
    private let apiKey: String

    init(modelID: String, apiKey: String) {
        self.modelID = modelID
        self.apiKey = apiKey
    }

    static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    static let modelsURL = URL(string: "https://api.anthropic.com/v1/models?limit=1")!
    static let apiVersion = "2023-06-01"

    // MARK: Request building

    /// Models that think by default and can't be told to stop: Sonnet 5.5 rejects
    /// `thinking: {"type": "disabled"}` and Opus 5.5 rejects it at every effort (both 400).
    /// A rewrite is latency-sensitive and tool-less, so they get adaptive thinking at
    /// `output_config.effort: "low"`, which the migration guide recommends over
    /// `thinking: {"type": "between_tools"}` (Sonnet 5.5 only, restricted fields, effort
    /// <= high). Adaptive keeps reasoning in separate `thinking` blocks, which `decode`
    /// drops, so nothing but the rewrite reaches the user's clipboard. Haiku 4.5 predates
    /// both parameters and is deliberately absent: omitting them already means "no thinking".
    private static let modelsUsingLowEffort: Set<String> = ["claude-sonnet-5-5", "claude-opus-5-5"]

    func buildRequest(_ improvement: ImprovementRequest, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: Self.messagesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": Constants.maxOutputTokens,
            "stream": stream,
            "system": improvement.systemPrompt,
            "messages": [
                ["role": "user", "content": improvement.userPrompt],
            ],
        ]
        if Self.modelsUsingLowEffort.contains(modelID) {
            body["output_config"] = ["effort": "low"]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Streaming

    func improveTextStream(request improvement: ImprovementRequest) -> AsyncThrowingStream<String, Error> {
        HTTPStream.textStream(
            emptyMessage: "Claude returned no text. Try again or pick a different model.",
            prepare: {
                guard !improvement.isEmpty else { throw AIServiceError.emptyInput }
                guard !apiKey.isEmpty else { throw AIServiceError.missingKey(provider) }
                return try buildRequest(improvement, stream: true)
            },
            decode: Self.decode(event:),
            mapHTTPError: Self.mapHTTPError)
    }

    // MARK: Key validation

    /// Lists models — authenticates the key without spending a token.
    func validateKey() async -> Result<Void, AIServiceError> {
        guard !apiKey.isEmpty else { return .failure(.missingKey(provider)) }
        var request = URLRequest(url: Self.modelsURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")

        do {
            let (data, http) = try await HTTPStream.send(request)
            guard (200..<300).contains(http.statusCode) else {
                return .failure(Self.mapHTTPError(http.statusCode, data, http))
            }
            return .success(())
        } catch {
            return .failure(HTTPStream.transportError(error))
        }
    }

    // MARK: Event decoding

    static func decode(event: SSEEvent) throws -> StreamOutcome {
        let payload = event.data.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return .ignore }
        guard let data = payload.data(using: .utf8),
              let json = HTTPStream.json(data) else { return .ignore }

        switch (json["type"] as? String) ?? event.event ?? "" {
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return .ignore }
            // `text_delta` carries the answer; `thinking_delta` / `input_json_delta`
            // must never reach the user's document.
            if (delta["type"] as? String) == "text_delta", let text = delta["text"] as? String {
                return .text(text)
            }
            return .ignore

        case "message_delta":
            switch ((json["delta"] as? [String: Any])?["stop_reason"] as? String) ?? "" {
            case "refusal":
                // Includes a refusal after partial output: the caller keeps what arrived
                // on screen but the request fails, so it is never offered as a result.
                throw AIServiceError.api("Claude declined to rewrite this text.")
            case "max_tokens", "model_context_window_exceeded":
                return .truncated
            default:
                return .ignore
            }

        case "message_stop":
            return .done

        case "error":
            throw streamError(json)

        default:
            // message_start, content_block_start/stop, ping, and anything new.
            return .ignore
        }
    }

    /// Mid-stream `error` event: `{"type":"error","error":{"type":…,"message":…}}`.
    private static func streamError(_ json: [String: Any]) -> AIServiceError {
        let error = json["error"] as? [String: Any]
        let type = error?["type"] as? String ?? ""
        let message = error?["message"] as? String ?? "Claude reported an error mid-response."
        switch type {
        case "overloaded_error": return .serverError(529)
        case "api_error": return .serverError(500)
        case "rate_limit_error": return .rateLimited(retryAfter: nil)
        case "authentication_error": return .invalidKey(.anthropic)
        case "billing_error": return .quotaExceeded
        default: return .api(message)
        }
    }

    // MARK: HTTP error mapping

    /// Anthropic error body: `{"type":"error","error":{"type":…,"message":…}}`.
    static func mapHTTPError(_ status: Int, _ body: Data, _ response: HTTPURLResponse) -> AIServiceError {
        let error = HTTPStream.json(body)?["error"] as? [String: Any]
        let type = error?["type"] as? String ?? ""
        let message = (error?["message"] as? String) ?? ""
        let lowercased = message.lowercased()
        let looksLikeBilling = type == "billing_error"
            || lowercased.contains("credit balance")
            || lowercased.contains("insufficient credit")

        switch status {
        case 400:
            // A depleted account reports as a 400 invalid_request_error.
            if looksLikeBilling { return .quotaExceeded }
            return .api(message.isEmpty ? "Claude rejected the request." : message)
        case 401:
            return .invalidKey(.anthropic)
        case 403:
            return looksLikeBilling ? .quotaExceeded : .invalidKey(.anthropic)
        case 404:
            return .api("That Claude model isn't available to this key. Pick another in Settings.")
        case 413:
            return .api("That selection is too large for one request. Select less text.")
        case 429:
            let retry = HTTPStream.retryAfter(from: response)
                ?? HTTPStream.secondsUntilReset("anthropic-ratelimit-requests-reset", in: response)
                ?? HTTPStream.secondsUntilReset("anthropic-ratelimit-tokens-reset", in: response)
            return looksLikeBilling ? .quotaExceeded : .rateLimited(retryAfter: retry)
        case 500...599:
            return .serverError(status)
        default:
            return message.isEmpty ? .serverError(status) : .api(message)
        }
    }
}
