import Foundation

/// Google Gemini `generateContent` API.
///
/// Wire reference:
/// `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse`
/// authenticated with the `x-goog-api-key` header (never the `?key=` query
/// parameter — that would put the secret in URLs and logs).
///
/// With `alt=sse` each `data:` line is a complete `GenerateContentResponse`;
/// incremental text is at `candidates[0].content.parts[*].text`. There is no
/// terminal event and no `[DONE]` sentinel — the connection simply closes after
/// the chunk carrying `finishReason`.
nonisolated struct GeminiService: AIService {
    let provider: AIProvider = .gemini
    let modelID: String
    private let apiKey: String

    init(modelID: String, apiKey: String) {
        self.modelID = modelID
        self.apiKey = apiKey
    }

    static let apiBase = "https://generativelanguage.googleapis.com/v1beta/models"

    /// The id as one safe path segment: a hand-typed id may carry a `models/` prefix
    /// (as the Gemini docs list them) or characters that aren't valid in a URL.
    static func pathSegment(_ modelID: String) -> String {
        var id = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.hasPrefix("models/") { id.removeFirst("models/".count) }
        return id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)?
            .replacingOccurrences(of: "/", with: "%2F") ?? id
    }

    static func streamURL(modelID: String) -> URL {
        URL(string: "\(apiBase)/\(pathSegment(modelID)):streamGenerateContent?alt=sse")
            ?? URL(string: apiBase)!
    }

    static func modelURL(modelID: String) -> URL {
        URL(string: "\(apiBase)/\(pathSegment(modelID))") ?? URL(string: apiBase)!
    }

    // MARK: Request building

    static func thinkingLevel(for modelID: String) -> String? {
        switch modelID {
        case "gemini-3.8-flash", "gemini-3.7-flash": return "low"
        case "gemini-3.6-flash", "gemini-3.5-flash-lite": return "minimal"
        default: return nil
        }
    }

    func buildRequest(_ improvement: ImprovementRequest, stream: Bool) throws -> URLRequest {
        let url = stream ? Self.streamURL(modelID: modelID)
                         : URL(string: "\(Self.apiBase)/\(Self.pathSegment(modelID)):generateContent") ?? Self.streamURL(modelID: modelID)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        var generationConfig: [String: Any] = ["maxOutputTokens": Constants.maxOutputTokens]
        // Thinking can't be turned off on Gemini 3; the lowest accepted level differs per
        // model ("minimal" is a 400 on 3.8 Flash). Unknown ids (typed via "Other…") get no
        // thinkingConfig, since the model default is always valid.
        if let level = Self.thinkingLevel(for: modelID) {
            generationConfig["thinkingConfig"] = ["thinkingLevel": level]
        }

        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": improvement.userPrompt]]],
            ],
            "systemInstruction": ["parts": [["text": improvement.systemPrompt]]],
            "generationConfig": generationConfig,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Streaming

    func improveTextStream(request improvement: ImprovementRequest) -> AsyncThrowingStream<String, Error> {
        HTTPStream.textStream(
            emptyMessage: "Gemini returned no text. Try again or pick a different model.",
            prepare: {
                guard !improvement.isEmpty else { throw AIServiceError.emptyInput }
                guard !apiKey.isEmpty else { throw AIServiceError.missingKey(provider) }
                return try buildRequest(improvement, stream: true)
            },
            decode: Self.decode(event:),
            mapHTTPError: Self.mapHTTPError)
    }

    // MARK: Key validation

    /// Fetches the model's metadata — authenticates the key without spending a token.
    func validateKey() async -> Result<Void, AIServiceError> {
        guard !apiKey.isEmpty else { return .failure(.missingKey(provider)) }
        var request = URLRequest(url: Self.modelURL(modelID: modelID))
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

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

    /// Finish reasons that mean the answer was withheld rather than completed.
    private static let blockingFinishReasons: Set<String> = [
        "SAFETY", "RECITATION", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "IMAGE_SAFETY",
    ]

    static func decode(event: SSEEvent) throws -> StreamOutcome {
        let payload = event.data.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return .ignore }
        guard let data = payload.data(using: .utf8),
              let json = HTTPStream.json(data) else { return .ignore }

        // Mid-stream failures arrive as a normal data chunk carrying `error`.
        if let error = json["error"] as? [String: Any] {
            throw mapError(status: error["code"] as? Int ?? 0,
                           error: error,
                           response: nil)
        }

        // A prompt rejected before generation.
        if let feedback = json["promptFeedback"] as? [String: Any],
           let reason = feedback["blockReason"] as? String {
            throw AIServiceError.api("Gemini blocked this text (\(reason)).")
        }

        guard let candidate = (json["candidates"] as? [[String: Any]])?.first else {
            return .ignore
        }

        var text = ""
        if let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] {
            for part in parts {
                // Thought summaries are flagged and must not reach the document.
                if (part["thought"] as? Bool) == true { continue }
                if let fragment = part["text"] as? String { text += fragment }
            }
        }

        let finishReason = candidate["finishReason"] as? String
        if let reason = finishReason, blockingFinishReasons.contains(reason), text.isEmpty {
            throw AIServiceError.api("Gemini stopped early (\(reason)) and returned nothing.")
        }

        if let reason = finishReason {
            if reason == "MAX_TOKENS" { return text.isEmpty ? .truncated : .textThenTruncated(text) }
            return text.isEmpty ? .done : .textThenDone(text)
        }
        return text.isEmpty ? .ignore : .text(text)
    }

    // MARK: HTTP error mapping

    /// Gemini error body:
    /// `{"error":{"code":429,"message":…,"status":"RESOURCE_EXHAUSTED","details":[…]}}`.
    static func mapHTTPError(_ status: Int, _ body: Data, _ response: HTTPURLResponse) -> AIServiceError {
        let error = HTTPStream.json(body)?["error"] as? [String: Any]
        return mapError(status: status, error: error, response: response)
    }

    private static func mapError(status: Int,
                                 error: [String: Any]?,
                                 response: HTTPURLResponse?) -> AIServiceError {
        let code = (error?["code"] as? Int) ?? status
        let message = (error?["message"] as? String) ?? ""
        let lowercased = message.lowercased()
        let details = error?["details"] as? [[String: Any]] ?? []

        let reasons = Set(details.compactMap { $0["reason"] as? String })
        let looksLikeBadKey = reasons.contains("API_KEY_INVALID")
            || lowercased.contains("api key not valid")
            || lowercased.contains("api_key_invalid")
        let looksLikeBilling = reasons.contains("BILLING_DISABLED")
            || lowercased.contains("billing")
            || lowercased.contains("free tier")

        switch code {
        case 400:
            // A malformed key comes back as INVALID_ARGUMENT, not 401.
            if looksLikeBadKey { return .invalidKey(.gemini) }
            return .api(message.isEmpty ? "Gemini rejected the request." : message)
        case 401:
            return .invalidKey(.gemini)
        case 403:
            if looksLikeBilling { return .quotaExceeded }
            return .invalidKey(.gemini)
        case 404:
            return .api("That Gemini model isn't available to this key. Pick another in Settings.")
        case 413:
            return .api("That selection is too large for one request. Select less text.")
        case 429:
            // RESOURCE_EXHAUSTED covers both throttling and a spent quota; a
            // RetryInfo detail means it's throttling and worth retrying soon.
            let retry = retryDelaySeconds(in: details)
                ?? response.flatMap { HTTPStream.retryAfter(from: $0) }
            if retry == nil && (looksLikeBilling || lowercased.contains("quota")) {
                return .quotaExceeded
            }
            return .rateLimited(retryAfter: retry)
        case 500...599:
            return .serverError(code)
        default:
            return message.isEmpty ? .serverError(code) : .api(message)
        }
    }

    /// Pulls `retryDelay` ("25s") out of a `google.rpc.RetryInfo` detail.
    private static func retryDelaySeconds(in details: [[String: Any]]) -> TimeInterval? {
        for detail in details {
            guard let type = detail["@type"] as? String, type.hasSuffix("RetryInfo"),
                  var raw = detail["retryDelay"] as? String else { continue }
            if raw.hasSuffix("s") { raw.removeLast() }
            if let seconds = TimeInterval(raw) { return seconds }
        }
        return nil
    }
}
