import Foundation

// MARK: - Wire format

/// One dispatched Server-Sent Event.
nonisolated struct SSEEvent: Sendable, Equatable {
    /// Value of the `event:` field, when the provider sends one.
    var event: String?
    /// All `data:` lines of this event, joined with newlines (per the SSE spec).
    var data: String
}

/// Line-oriented SSE state machine.
///
/// Handles the parts providers actually use: `event:` names, multi-line `data:`
/// payloads, `:` comment keep-alives, and `id:`/`retry:` fields we ignore.
nonisolated struct SSEParser {
    private var eventName: String?
    private var dataLines: [String] = []

    /// Feeds one line (newline already stripped). Returns an event when the line
    /// terminates one — i.e. on the blank line that ends a block.
    mutating func consume(line rawLine: String) -> SSEEvent? {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() }

        // Blank line dispatches whatever has accumulated.
        if line.isEmpty {
            return flush()
        }
        // Comment / keep-alive.
        if line.hasPrefix(":") {
            return nil
        }

        let field: String
        var value: String
        if let colon = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colon])
            value = String(line[line.index(after: colon)...])
            if value.hasPrefix(" ") { value.removeFirst() }
        } else {
            field = line
            value = ""
        }

        switch field {
        case "data": dataLines.append(value)
        case "event": eventName = value
        default: break // id, retry, and anything unknown
        }
        return nil
    }

    /// Dispatches a trailing block that was never followed by a blank line.
    mutating func finish() -> SSEEvent? { flush() }

    private mutating func flush() -> SSEEvent? {
        defer {
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
        }
        guard eventName != nil || !dataLines.isEmpty else { return nil }
        return SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
    }
}

/// Byte-level front end for `SSEParser`.
///
/// Buffers a partial line across chunk boundaries, so a JSON payload split
/// mid-token by the transport still parses correctly. Splitting on `0x0A` is
/// safe for UTF-8: a newline byte never appears inside a multi-byte sequence.
nonisolated struct SSEByteScanner {
    private var parser = SSEParser()
    private var pending: [UInt8] = []

    /// Feeds one byte. Returns an event if this byte completed one.
    mutating func consume(byte: UInt8) -> SSEEvent? {
        guard byte == 0x0A else {
            pending.append(byte)
            return nil
        }
        let line = String(decoding: pending, as: UTF8.self)
        pending.removeAll(keepingCapacity: true)
        return parser.consume(line: line)
    }

    /// Feeds an arbitrary chunk of bytes.
    mutating func consume<S: Sequence>(_ chunk: S) -> [SSEEvent] where S.Element == UInt8 {
        var events: [SSEEvent] = []
        for byte in chunk {
            if let event = consume(byte: byte) { events.append(event) }
        }
        return events
    }

    /// Convenience for feeding literal text (used by the self-check).
    mutating func consume(_ text: String) -> [SSEEvent] {
        consume(Array(text.utf8))
    }

    /// Flushes a trailing partial line and any undispatched block, for streams
    /// that end without a final blank line.
    mutating func finish() -> [SSEEvent] {
        var events: [SSEEvent] = []
        if !pending.isEmpty {
            let line = String(decoding: pending, as: UTF8.self)
            pending.removeAll(keepingCapacity: true)
            if let event = parser.consume(line: line) { events.append(event) }
        }
        if let event = parser.finish() { events.append(event) }
        return events
    }
}

/// What a provider's decoder wants the driver to do with one event.
nonisolated enum StreamOutcome: Sendable, Equatable {
    /// Not interesting (keep-alive, bookkeeping event, unknown type).
    case ignore
    /// Emit this fragment and keep reading.
    case text(String)
    /// Emit this fragment, then stop.
    case textThenDone(String)
    /// Stop reading; the response is complete.
    case done
}

// MARK: - Transport

/// Shared HTTP plumbing for the three streaming providers.
nonisolated enum HTTPStream {
    /// Ephemeral: no cookies, no disk cache, nothing of the user's text on disk.
    ///
    /// `timeoutIntervalForRequest` is URLSession's inactivity timeout, so it
    /// covers both "no first byte in 20s" and "stalled mid-stream for 20s".
    /// `timeoutIntervalForResource` is the hard 60s ceiling on the whole request.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = Constants.firstByteTimeout
        config.timeoutIntervalForResource = Constants.overallTimeout
        config.waitsForConnectivity = false
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Cap on how much of a non-2xx body we read before giving up on parsing it.
    private static let maxErrorBodyBytes = 64_000

    /// Runs one streaming request end to end.
    ///
    /// - Parameters:
    ///   - request: fully built, `stream` already switched on in the body.
    ///   - decode: pure per-event decoder; throws to abort with a mapped error.
    ///   - mapHTTPError: turns a non-2xx response into an `AIServiceError`.
    ///   - onText: receives every fragment, in order.
    /// - Returns: `true` if at least one non-empty fragment was emitted.
    @discardableResult
    static func run(_ request: URLRequest,
                    decode: (SSEEvent) throws -> StreamOutcome,
                    mapHTTPError: (Int, Data, HTTPURLResponse) -> AIServiceError,
                    onText: (String) -> Void) async throws -> Bool {
        let (bytes, response) = try await session.bytes(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= maxErrorBodyBytes { break }
            }
            throw mapHTTPError(http.statusCode, body, http)
        }

        var scanner = SSEByteScanner()
        var emitted = false

        func handle(_ event: SSEEvent) throws -> Bool {
            switch try decode(event) {
            case .ignore:
                return false
            case .text(let fragment):
                if !fragment.isEmpty {
                    emitted = true
                    onText(fragment)
                }
                return false
            case .textThenDone(let fragment):
                if !fragment.isEmpty {
                    emitted = true
                    onText(fragment)
                }
                return true
            case .done:
                return true
            }
        }

        for try await byte in bytes {
            try Task.checkCancellation()
            guard let event = scanner.consume(byte: byte) else { continue }
            if try handle(event) { return emitted }
        }

        for event in scanner.finish() {
            if try handle(event) { return emitted }
        }
        return emitted
    }

    /// Fires a non-streaming request and returns the body plus response.
    static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        return (data, http)
    }

    // MARK: Error helpers

    /// Sentinel meaning "the consumer cancelled" — the caller finishes the stream
    /// silently rather than surfacing an error.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Maps a transport-level failure onto the user-facing error surface.
    static func transportError(_ error: Error) -> AIServiceError {
        if let serviceError = error as? AIServiceError { return serviceError }
        guard let urlError = error as? URLError else {
            return .network(error.localizedDescription)
        }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .network(urlError.localizedDescription)
        }
    }

    /// Seconds to wait, from `Retry-After` (delta-seconds or HTTP-date).
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if let seconds = TimeInterval(raw) { return max(0, seconds) }
        if let date = httpDateFormatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    /// Seconds until an RFC 3339 reset timestamp in the given header.
    static func secondsUntilReset(_ header: String, in response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: header) else { return nil }
        // Providers send both `…:00Z` and `…:00.123Z`, so try each shape.
        guard let date = rfc3339Formatter.date(from: raw)
            ?? rfc3339FractionalFormatter.date(from: raw) else { return nil }
        let seconds = date.timeIntervalSinceNow
        return seconds > 0 ? seconds : nil
    }

    /// Top-level JSON object of a body, when it is one.
    static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()

    private static let rfc3339Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let rfc3339FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
