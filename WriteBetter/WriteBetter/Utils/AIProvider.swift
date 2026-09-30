import SwiftUI

/// One model a provider exposes, as offered in Settings.
///
/// `id` is the exact string sent on the wire — never construct one by hand,
/// always pick from `AIProvider.models`.
nonisolated struct AIModelOption: Identifiable, Hashable, Sendable {
    /// Exact API model id.
    let id: String
    /// Human-readable name for the picker.
    let name: String
    /// One short line describing the tradeoff.
    let blurb: String
}

/// The AI backends WriteBetter can talk to.
///
/// Model ids below were verified against each vendor's live docs (see the
/// per-service files for the endpoint each one is used with). They are ordered
/// best-default first: `models[0]` is what a freshly configured provider uses.
nonisolated enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case anthropic
    case openai
    case gemini
    /// Any server that speaks the OpenAI Chat Completions protocol: Ollama, LM Studio,
    /// OpenRouter, vLLM, a corporate gateway…
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    /// Compact name for tight chips and tiles.
    var shortName: String {
        switch self {
        case .custom: return "Custom"
        default: return displayName
        }
    }

    /// Anthropic, OpenAI and Gemini are unusable without a key. A custom endpoint takes
    /// an optional one (local servers don't want any).
    var needsAPIKey: Bool {
        switch self {
        case .anthropic, .openai, .gemini: return true
        case .custom: return false
        }
    }

    var modelFamilyName: String {
        switch self {
        case .anthropic: return "Claude"
        case .openai: return "GPT"
        case .gemini: return "Gemini"
        case .custom: return "Any model"
        }
    }

    /// SF Symbol that renders on every supported macOS version.
    var iconSymbol: String {
        switch self {
        case .anthropic: return "sparkles"
        case .openai: return "circle.hexagongrid.fill"
        case .gemini: return "diamond.fill"
        case .custom: return "server.rack"
        }
    }

    /// Brand accent, used for selection chrome and the provider chip.
    var accent: Color {
        switch self {
        case .anthropic: return Color(red: 0.80, green: 0.47, blue: 0.36) // clay
        case .openai:    return Color(red: 0.06, green: 0.64, blue: 0.50) // teal
        case .gemini:    return Color(red: 0.26, green: 0.52, blue: 0.96) // blue
        case .custom:    return Color(red: 0.55, green: 0.45, blue: 0.85) // violet
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-api03-…"
        case .openai: return "sk-proj-…"
        case .gemini: return "AIza…"
        case .custom: return "API key (optional)"
        }
    }

    /// Stable prefix every key of this provider starts with, when there is one.
    ///
    /// Gemini is deliberately `nil`: Google issues both `AIza…` standard keys and
    /// newer service-account "auth" keys with a different prefix, so a prefix
    /// check there would reject valid keys.
    var keyPrefixHint: String? {
        switch self {
        case .anthropic: return "sk-ant-"
        case .openai: return "sk-"
        case .gemini, .custom: return nil
        }
    }

    /// Where the user goes to create a key.
    var consoleURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .custom: return URL(string: "https://openrouter.ai/keys")!
        }
    }

    /// Curated shortlist. Index 0 is the default for a newly configured provider.
    var models: [AIModelOption] {
        switch self {
        case .anthropic:
            return [
                AIModelOption(id: "claude-sonnet-5-5",
                              name: "Claude Sonnet 5.5",
                              blurb: "Recommended — best balance"),
                AIModelOption(id: "claude-opus-5-5",
                              name: "Claude Opus 5.5",
                              blurb: "Highest quality, slower"),
                AIModelOption(id: "claude-haiku-4-5",
                              name: "Claude Haiku 4.5",
                              blurb: "Fastest and cheapest"),
            ]
        case .openai:
            return [
                AIModelOption(id: "gpt-5.6-terra",
                              name: "GPT-5.6 Terra",
                              blurb: "Recommended — best balance"),
                AIModelOption(id: "gpt-6.1-sol",
                              name: "GPT-6.1 Sol",
                              blurb: "Highest quality, slower"),
                AIModelOption(id: "gpt-6-luna",
                              name: "GPT-6 Luna",
                              blurb: "Fastest and cheapest"),
            ]
        case .gemini:
            return [
                AIModelOption(id: "gemini-3.8-flash",
                              name: "Gemini 3.8 Flash",
                              blurb: "Recommended — latest and most capable Flash"),
                AIModelOption(id: "gemini-3.6-flash",
                              name: "Gemini 3.6 Flash",
                              blurb: "Previous generation, very capable"),
                AIModelOption(id: "gemini-3.5-flash-lite",
                              name: "Gemini 3.5 Flash-Lite",
                              blurb: "Cheapest, highest throughput"),
            ]
        case .custom:
            // Free text: whatever the server serves. See "Load models" in Settings.
            return []
        }
    }

    /// Ids that shipped in an earlier catalog and no longer exist, with what replaces them.
    /// A stored choice is remapped instead of being sent to the API and 404ing.
    static let retiredModelIDs: [String: String] = [
        "claude-sonnet-5": "claude-sonnet-5-5",
        "claude-opus-5": "claude-opus-5-5",
    ]

    /// The id used when nothing has been chosen yet.
    var defaultModelID: String { models.first?.id ?? "" }

    /// Looks an id up in the curated catalog; `nil` for a hand-typed ("Other…") id.
    func model(withID id: String) -> AIModelOption? {
        models.first { $0.id == id }
    }
}
