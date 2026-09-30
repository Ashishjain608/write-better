import Foundation

/// Any server that speaks the OpenAI **Chat Completions** protocol (Ollama, LM Studio,
/// OpenRouter, vLLM, gateways). The Responses API is OpenAI-only, so this is the
/// lowest common denominator these servers actually implement.
///
/// Wire reference: `POST {base}/chat/completions` with `stream: true`; SSE `data:`
/// lines carry `choices[0].delta.content`, and the stream ends with `data: [DONE]`.
/// The API key is optional: local servers ignore it, so no `Authorization` header is
/// sent unless one was saved.
nonisolated struct CustomEndpointService: AIService {
    let provider: AIProvider = .custom
    let modelID: String
    let baseURL: URL
    private let apiKey: String

    init(modelID: String, apiKey: String, baseURL: URL) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    // MARK: Base URL

    struct Preset: Identifiable, Sendable {
        let name: String
        let baseURL: String
        var id: String { name }
    }

    static let presets: [Preset] = [
        Preset(name: "Ollama", baseURL: "http://localhost:11434/v1"),
        Preset(name: "LM Studio", baseURL: "http://localhost:1234/v1"),
        Preset(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1"),
    ]

    /// What the user typed → a clean base URL, or `nil` if it can't be one.
    ///
    /// Forgiving on purpose: a missing scheme becomes `http://` (people type
    /// `localhost:11434/v1`), a trailing slash goes, and a pasted full endpoint
    /// (`…/chat/completions`, `…/models`) is cut back to the base.
    static func normalizedBaseURL(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        for suffix in ["/chat/completions", "/models"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private func endpoint(_ path: String) -> URL { baseURL.appendingPathComponent(path) }

    private static func authorize(_ request: inout URLRequest, key: String) {
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
    }

    // MARK: Request building

    func buildRequest(_ improvement: ImprovementRequest, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: endpoint("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        Self.authorize(&request, key: apiKey)

        let body: [String: Any] = [
            "model": modelID,
            "messages": [
                ["role": "system", "content": improvement.systemPrompt],
                ["role": "user", "content": improvement.userPrompt],
            ],
            "stream": stream,
            // `max_tokens` is what Ollama, LM Studio and OpenRouter all accept;
            // `max_completion_tokens` is OpenAI-only.
            "max_tokens": Constants.maxOutputTokens,
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
                    guard !modelID.trimmingCharacters(in: .whitespaces).isEmpty else {
                        throw AIServiceError.api("Enter a model id for the custom endpoint in Settings.")
                    }

                    let urlRequest = try buildRequest(improvement, stream: true)
                    let emitted = try await HTTPStream.run(
                        urlRequest,
                        decode: Self.decode(event:),
                        mapHTTPError: Self.mapHTTPError,
                        onText: { continuation.yield($0) }
                    )
                    if !emitted {
                        throw AIServiceError.api("The server returned no text. Check the model id, or try another model.")
                    }
                    continuation.finish()
                } catch {
                    if HTTPStream.isCancellation(error) {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: Self.transportError(error, baseURL: baseURL))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Key validation and model listing

    private func modelsRequest() -> URLRequest {
        var request = URLRequest(url: endpoint("models"))
        request.httpMethod = "GET"
        Self.authorize(&request, key: apiKey)
        return request
    }

    /// Lists models: proves the server is reachable and the key (if any) is accepted.
    func validateKey() async -> Result<Void, AIServiceError> {
        do {
            let (data, http) = try await HTTPStream.send(modelsRequest())
            guard (200..<300).contains(http.statusCode) else {
                return .failure(Self.mapHTTPError(http.statusCode, data, http))
            }
            return .success(())
        } catch {
            return .failure(Self.transportError(error, baseURL: baseURL))
        }
    }

    /// `GET {base}/models` → the ids the server offers, sorted.
    func fetchModelIDs() async -> Result<[String], AIServiceError> {
        do {
            let (data, http) = try await HTTPStream.send(modelsRequest())
            guard (200..<300).contains(http.statusCode) else {
                return .failure(Self.mapHTTPError(http.statusCode, data, http))
            }
            guard let ids = Self.parseModelIDs(data) else { return .failure(.invalidResponse) }
            return .success(ids)
        } catch {
            return .failure(Self.transportError(error, baseURL: baseURL))
        }
    }

    /// `{"data":[{"id":"llama3.2"},…]}` (OpenAI, Ollama, LM Studio, OpenRouter).
    static func parseModelIDs(_ data: Data) -> [String]? {
        guard let list = HTTPStream.json(data)?["data"] as? [[String: Any]] else { return nil }
        return list.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }.sorted()
    }

    // MARK: Event decoding

    static func decode(event: SSEEvent) throws -> StreamOutcome {
        let payload = event.data.trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return .ignore }
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let json = HTTPStream.json(data) else { return .ignore }

        // Mid-stream failures arrive as a normal data chunk carrying `error`.
        if json["error"] != nil {
            throw errorFromBody(status: 0, body: data, response: nil)
        }

        // Usage-only and keep-alive chunks have an empty `choices`.
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return .ignore }

        // Only `content`: `reasoning_content` / `reasoning` (thinking models) must never
        // reach the user's document.
        let text = ((choice["delta"] as? [String: Any])?["content"] as? String) ?? ""

        switch choice["finish_reason"] as? String {
        case nil, "":
            return text.isEmpty ? .ignore : .text(text)
        case "content_filter":
            throw AIServiceError.api("The server's content filter blocked this text.")
        default:
            return text.isEmpty ? .done : .textThenDone(text)
        }
    }

    // MARK: Errors

    /// Message from `{"error":{"message":…}}` (OpenAI, OpenRouter, LM Studio) or
    /// `{"error":"…"}` (Ollama's native shape).
    private static func errorMessage(_ body: Data) -> String {
        guard let error = HTTPStream.json(body)?["error"] else { return "" }
        if let text = error as? String { return text }
        return (error as? [String: Any])?["message"] as? String ?? ""
    }

    static func mapHTTPError(_ status: Int, _ body: Data, _ response: HTTPURLResponse) -> AIServiceError {
        errorFromBody(status: status, body: body, response: response)
    }

    private static func errorFromBody(status: Int, body: Data, response: HTTPURLResponse?) -> AIServiceError {
        let message = errorMessage(body)
        var code = status
        if code == 0, let error = HTTPStream.json(body)?["error"] as? [String: Any] {
            code = (error["code"] as? Int) ?? 0
        }
        switch code {
        case 401, 403:
            return .invalidKey(.custom)
        case 402:
            return .quotaExceeded
        case 404:
            return .api(message.isEmpty
                        ? "The server has no such model or endpoint. Check the model id, and that the base URL ends in /v1."
                        : message)
        case 413:
            return .api("That selection is too large for one request. Select less text.")
        case 429:
            return .rateLimited(retryAfter: response.flatMap { HTTPStream.retryAfter(from: $0) })
        case 500...599:
            return message.isEmpty ? .serverError(code) : .api(message)
        default:
            return message.isEmpty ? .api("The server rejected the request.") : .api(message)
        }
    }

    /// Transport failure → a message about *this* server. "You're offline" would be
    /// wrong for a localhost server that simply isn't running.
    static func transportError(_ error: Error, baseURL: URL) -> AIServiceError {
        if let serviceError = error as? AIServiceError { return serviceError }
        guard let urlError = error as? URLError else { return HTTPStream.transportError(error) }
        let host = baseURL.host ?? "the server"

        switch urlError.code {
        case .appTransportSecurityRequiresSecureConnection:
            return .api("macOS only allows plain http:// for addresses on your own network. Use https://, or a local address.")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .notConnectedToInternet, .networkConnectionLost:
            return .endpointUnreachable(host: host,
                                        localNetworkBlocked: isLocalNetworkDenial(urlError, host: host))
        default:
            return HTTPStream.transportError(urlError)
        }
    }

    /// With the Local Network switch off, connections to LAN addresses fail with
    /// `EHOSTUNREACH` ("No route to host") or `EACCES` underneath the URLError.
    /// Loopback is never subject to that switch, so it can't be a denial.
    static func isLocalNetworkDenial(_ error: URLError, host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasPrefix("127.") { return false }
        var current: NSError? = error as NSError
        while let underlying = (current?.userInfo[NSUnderlyingErrorKey] as? NSError) {
            if underlying.domain == NSPOSIXErrorDomain, underlying.code == 65 || underlying.code == 13 {
                return true
            }
            current = underlying
        }
        return false
    }
}
