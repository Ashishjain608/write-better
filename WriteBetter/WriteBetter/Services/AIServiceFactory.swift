import Foundation

/// Builds the concrete service for a provider.
nonisolated enum AIServiceFactory {
    /// Service for the currently selected provider + model, using the stored key.
    ///
    /// - Throws: `.noProviderConfigured` when nothing is set up at all,
    ///           `.missingKey` when the selected provider specifically has no key.
    @MainActor
    static func makeService() throws -> AIService {
        let settings = SettingsStore.shared
        guard !settings.configuredProviders.isEmpty else {
            throw AIServiceError.noProviderConfigured
        }
        let provider = settings.selectedProvider
        let key = settings.apiKey(for: provider)
        guard !key.isEmpty else {
            throw AIServiceError.missingKey(provider)
        }
        return service(for: provider, apiKey: key, modelID: settings.modelID(for: provider))
    }

    /// Ad-hoc service, used by Settings' "Test key" button before the key is saved.
    static func service(for provider: AIProvider, apiKey: String, modelID: String) -> AIService {
        switch provider {
        case .anthropic:
            return AnthropicService(modelID: modelID, apiKey: apiKey)
        case .openai:
            return OpenAIService(modelID: modelID, apiKey: apiKey)
        case .gemini:
            return GeminiService(modelID: modelID, apiKey: apiKey)
        }
    }
}
