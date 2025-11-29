import Foundation

enum Constants {
    static let apiKeyKey = "ANTHROPIC_API_KEY"
    static let anthropicAPIURL = "https://api.anthropic.com/v1/messages"
    static let defaultModel = "claude-sonnet-4-5-20250929"
    static let maxTokens = 1024

    static func loadAPIKey() -> String? {
        UserDefaults.standard.string(forKey: apiKeyKey)
    }

    static func saveAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: apiKeyKey)
    }
}
