import Foundation

/// OpenAI Responses API.
///
/// Wire reference: `POST https://api.openai.com/v1/responses` with
/// `Authorization: Bearer …`. The Responses API is what OpenAI recommends for
/// new integrations, it takes the system prompt as a first-class `instructions`
/// field, and — because the GPT-5.x family are reasoning models — it exposes
/// `reasoning.effort`, which lets a latency-sensitive rewrite skip reasoning
/// entirely. It also uses one output cap (`max_output_tokens`) rather than the
/// Chat Completions `max_tokens` → `max_completion_tokens` split.
///
/// Streaming is typed SSE: `event: response.output_text.delta` with the fragment
/// in `delta`. There is **no** `data: [DONE]` sentinel — the stream ends with
/// `response.completed` / `response.incomplete` / `response.failed`, or an
/// `error` event.
nonisolated struct OpenAIService: AIService {
    let provider: AIProvider = .openai
    let modelID: String
    private let apiKey: String

    init(modelID: String, apiKey: String) {
        self.modelID = modelID
        self.apiKey = apiKey
    }

    static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    static let modelsURL = URL(string: "https://api.openai.com/v1/models")!

    // MARK: Request building

    func buildRequest(_ improvement: ImprovementRequest, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: Self.responsesURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        let body: [String: Any] = [
            "model": modelID,
            "instructions": improvement.systemPrompt,
            "input": improvement.userPrompt,
            "stream": stream,
            // Don't leave the user's text sitting in OpenAI's response store.
            "store": false,
            "max_output_tokens": Constants.maxOutputTokens,
            // Rewriting needs no deliberation; "none" is OpenAI's own
            // recommendation for latency-critical work.
            "reasoning": ["effort": "none"],
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Streaming

    func improveTextStream(request improvement: ImprovementRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !improvement.isEmpty else { throw AIServiceError.emptyInput }
                    guard !apiKey.isEmpty else { throw AIServiceError.missingKey(provider) }

                    let urlRequest = try buildRequest(improvement, stream: true)
                    let emitted = try await HTTPStream.run(
                        urlRequest,
                        decode: Self.decode(event:),
                        mapHTTPError: Self.mapHTTPError,
                        onText: { continuation.yield($0) }
                    )
                    if !emitted {
                        throw AIServiceError.api("The model returned no text. Try again or pick a different model.")
                    }
                    continuation.finish()
                } catch {
                    if HTTPStream.isCancellation(error) {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: HTTPStream.transportError(error))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Key validation

    /// Lists models — authenticates the key without spending a token.
    func validateKey() async -> Result<Void, AIServiceError> {
        guard !apiKey.isEmpty else { return .failure(.missingKey(provider)) }
        var request = URLRequest(url: Self.modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

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
        // Responses never sends this; Chat-Completions-shaped proxies do.
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = HTTPStream.json(data) else { return .ignore }

        switch (json["type"] as? String) ?? event.event ?? "" {
        case "response.output_text.delta":
            guard let delta = json["delta"] as? String else { return .ignore }
            return .text(delta)

        case "response.completed":
            return .done

        case "response.incomplete":
            // Truncated by max_output_tokens: keep what we streamed.
            return .done

        case "response.failed":
            let response = json["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            throw mapStreamError(code: error?["code"] as? String,
                                 message: error?["message"] as? String)

        case "response.refusal.done":
            let refusal = json["refusal"] as? String
            throw AIServiceError.api(refusal ?? "The model declined to rewrite this text.")

        case "error":
            throw mapStreamError(code: json["code"] as? String,
                                 message: json["message"] as? String)

        default:
            // response.created, output_item.*, content_part.*, output_text.done, …
            return .ignore
        }
    }

    private static func mapStreamError(code: String?, message: String?) -> AIServiceError {
        let text = message ?? "OpenAI reported an error mid-response."
        switch code ?? "" {
        case "rate_limit_exceeded": return .rateLimited(retryAfter: nil)
        case "insufficient_quota": return .quotaExceeded
        case "server_error": return .serverError(500)
        default: return .api(text)
        }
    }

    // MARK: HTTP error mapping

    /// OpenAI error body: `{"error":{"message":…,"type":…,"param":…,"code":…}}`.
    static func mapHTTPError(_ status: Int, _ body: Data, _ response: HTTPURLResponse) -> AIServiceError {
        let error = HTTPStream.json(body)?["error"] as? [String: Any]
        let type = error?["type"] as? String ?? ""
        let code = error?["code"] as? String ?? ""
        let message = error?["message"] as? String ?? ""

        // Billing exhaustion arrives as a 429 with type `insufficient_quota`, or
        // one of the spend/usage-limit codes.
        let quotaCodes: Set<String> = [
            "insufficient_quota",
            "credit_balance_exhausted",
            "organization_spend_limit_exceeded",
            "project_spend_limit_exceeded",
            "organization_usage_limit_exceeded",
            "billing_hard_limit_reached",
        ]
        let looksLikeQuota = quotaCodes.contains(code)
            || quotaCodes.contains(type)
            || message.lowercased().contains("exceeded your current quota")

        switch status {
        case 401:
            return .invalidKey(.openai)
        case 403:
            return .invalidKey(.openai)
        case 404:
            return .api("That model isn't available to this key. Pick another in Settings.")
        case 413:
            return .api("That selection is too large for one request. Select less text.")
        case 429:
            if looksLikeQuota { return .quotaExceeded }
            let retry = HTTPStream.retryAfter(from: response)
                ?? HTTPStream.secondsUntilReset("x-ratelimit-reset-requests", in: response)
            return .rateLimited(retryAfter: retry)
        case 500...599:
            return .serverError(status)
        default:
            if looksLikeQuota { return .quotaExceeded }
            return message.isEmpty ? .serverError(status) : .api(message)
        }
    }
}
