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
        // A key the Keychain wouldn't release is not a missing key: retry once, then say so.
        let selected = settings.selectedProvider
        if settings.keyIsUnreadable(selected) {
            settings.retryKeychainRead(for: selected)
            if settings.keyIsUnreadable(selected) { throw AIServiceError.keychainUnavailable(selected) }
        }
        guard !settings.configuredProviders.isEmpty else {
            throw AIServiceError.noProviderConfigured
        }
        let provider = settings.selectedProvider
        guard settings.isUsable(provider) else {
            throw AIServiceError.missingKey(provider)
        }
        return service(for: provider,
                       apiKey: settings.apiKey(for: provider),
                       modelID: settings.modelID(for: provider),
                       baseURL: settings.customEndpointURL,
                       effort: settings.effort(for: provider))
    }

    /// Ad-hoc service, used by Settings' "Test" button before the key is saved.
    /// `baseURL` is only read for the custom endpoint.
    static func service(for provider: AIProvider, apiKey: String, modelID: String,
                        baseURL: URL? = nil, effort: String = CLIService.defaultEffort) -> AIService {
        switch provider {
        case .anthropic:
            return AnthropicService(modelID: modelID, apiKey: apiKey)
        case .openai:
            return OpenAIService(modelID: modelID, apiKey: apiKey)
        case .gemini:
            return GeminiService(modelID: modelID, apiKey: apiKey)
        case .apple:
            // Callers gate on availability; on a Mac that can't host it the request
            // fails with the reason instead of crashing.
            return AppleIntelligence.makeService() ?? UnavailableService(provider: .apple)
        case .claudeCode, .codex:
            return CLIService(provider: provider, modelID: modelID, effort: effort)
        case .custom:
            return CustomEndpointService(modelID: modelID, apiKey: apiKey,
                                         baseURL: baseURL ?? URL(string: CustomEndpointService.presets[0].baseURL)!)
        }
    }
}

/// Stand-in for a provider that can't run on this Mac. Fails with a plain reason.
nonisolated private struct UnavailableService: AIService {
    let provider: AIProvider
    var modelID: String { "" }

    func improveTextStream(request: ImprovementRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIServiceError.missingKey(provider)) }
    }

    func validateKey() async -> Result<Void, AIServiceError> { .failure(.missingKey(provider)) }
}
