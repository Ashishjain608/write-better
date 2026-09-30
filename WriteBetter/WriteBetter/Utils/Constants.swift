import Foundation

/// App-wide tunables. API keys live in the Keychain (see `Keychain`), never here.
nonisolated enum Constants {
    /// Upper bound on generated tokens for a single rewrite.
    /// Headroom matters: on models where thinking stays on (Opus 5), this caps
    /// thinking *plus* the rewrite, so a tight budget truncates the answer.
    static let maxOutputTokens = 8192

    /// Give up if the provider sends nothing for this long (also covers a mid-stream stall).
    static let firstByteTimeout: TimeInterval = 20

    /// Hard ceiling on one rewrite, from connect to last byte. Generous on purpose: long
    /// rewrites and slow local models are legitimate, and `firstByteTimeout` (an
    /// inactivity timer) already ends a stalled stream within 20 s.
    static let overallTimeout: TimeInterval = 300

    /// Keychain generic-password service holding every provider key.
    static let keychainService = "com.aj.WriteBetter.apikeys"

    /// Pre-1.0 builds kept the Anthropic key in UserDefaults under this name.
    /// `SettingsStore` migrates it into the Keychain once, then deletes it.
    static let legacyAnthropicDefaultsKey = "ANTHROPIC_API_KEY"
}
