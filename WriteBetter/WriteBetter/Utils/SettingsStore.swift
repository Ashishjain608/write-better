import Foundation
import Combine

/// Single source of truth for user settings.
///
/// API keys live in the Keychain (`Constants.keychainService`, account =
/// `AIProvider.rawValue`). Everything else lives in `UserDefaults`.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    // MARK: Persisted keys

    private enum Key {
        static let selectedProvider = "selectedProvider"
        static let modelIDs = "modelIDsByProvider"
        static let customBaseURL = "customEndpointBaseURL"
        static let autoCaptureSelection = "autoCaptureSelection"
        static let launchAtLogin = "launchAtLogin"
        static let didMigrateLegacyKey = "didMigrateLegacyAnthropicKey"
    }

    // MARK: Published state

    @Published var selectedProvider: AIProvider {
        didSet {
            guard selectedProvider != oldValue else { return }
            defaults.set(selectedProvider.rawValue, forKey: Key.selectedProvider)
        }
    }

    /// Providers that are ready to run: a key (Anthropic, OpenAI, Gemini) or a base URL
    /// (custom endpoint).
    @Published private(set) var configuredProviders: Set<AIProvider> = []

    /// Base URL of the custom OpenAI-compatible endpoint, as typed.
    @Published var customBaseURL: String {
        didSet {
            guard customBaseURL != oldValue else { return }
            defaults.set(customBaseURL, forKey: Key.customBaseURL)
            recomputeConfiguredProviders()
        }
    }

    /// The normalized custom endpoint, or `nil` when unset or malformed.
    var customEndpointURL: URL? { CustomEndpointService.normalizedBaseURL(customBaseURL) }

    /// Grab the current selection automatically when the popup opens.
    @Published var autoCaptureSelection: Bool {
        didSet {
            guard autoCaptureSelection != oldValue else { return }
            defaults.set(autoCaptureSelection, forKey: Key.autoCaptureSelection)
        }
    }

    /// Persisted flag only — the actual `SMAppService` registration is the UI layer's job.
    @Published var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
        }
    }

    // MARK: Storage

    private let defaults: UserDefaults
    private let keychainService: String
    /// Avoids hitting the Keychain from inside SwiftUI `body` evaluations.
    private var keyCache: [AIProvider: String] = [:]
    private var modelIDs: [String: String]

    // MARK: Init

    /// - Parameters:
    ///   - defaults: injectable for tests; production uses `.standard`.
    ///   - keychainService: injectable for tests.
    init(defaults: UserDefaults = .standard, keychainService: String? = nil) {
        self.defaults = defaults
        self.keychainService = keychainService ?? Constants.keychainService

        let storedProvider = defaults.string(forKey: Key.selectedProvider)
        // A stored Apple choice is dropped when Apple Intelligence is no longer available.
        self.selectedProvider = storedProvider.flatMap(AIProvider.init(rawValue:))
            .flatMap { AIProvider.allCases.contains($0) ? $0 : nil } ?? .anthropic
        self.customBaseURL = defaults.string(forKey: Key.customBaseURL) ?? ""
        self.modelIDs = defaults.dictionary(forKey: Key.modelIDs) as? [String: String] ?? [:]
        self.autoCaptureSelection = defaults.bool(forKey: Key.autoCaptureSelection)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

        #if DEBUG
        // `--self-check` never needs real keys, and reading the user's Keychain item from
        // a freshly built (differently signed) binary blocks on an access prompt.
        if CommandLine.arguments.contains("--self-check") && keychainService == nil { return }
        #endif
        migrateLegacyAnthropicKeyIfNeeded()
        refreshKeyCache()
    }

    // MARK: API keys

    /// The stored key, or `""` when unset.
    func apiKey(for provider: AIProvider) -> String {
        keyCache[provider] ?? ""
    }

    /// Saves a key; passing `""` (or whitespace only) deletes it.
    func setAPIKey(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            Keychain.delete(service: keychainService, account: provider.rawValue)
            keyCache[provider] = nil
        } else {
            let ok = Keychain.write(trimmed, service: keychainService, account: provider.rawValue)
            if ok {
                keyCache[provider] = trimmed
            } else {
                // Keychain refused the write — do not pretend it stuck.
                keyCache[provider] = nil
            }
        }
        recomputeConfiguredProviders()
    }

    func hasKey(for provider: AIProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    /// The selected provider is ready to run.
    var isConfigured: Bool { isUsable(selectedProvider) }

    /// Ready to run: has the key it needs, or the address it needs.
    func isUsable(_ provider: AIProvider) -> Bool {
        switch provider {
        case .anthropic, .openai, .gemini: return hasKey(for: provider)
        case .custom: return customEndpointURL != nil
        case .apple: return AppleIntelligence.isAvailable
        }
    }

    // MARK: Model selection

    /// Persisted model for a provider. Any non-empty id is honoured, including one
    /// typed via "Other…" that isn't in the curated catalog, so a stale catalog can
    /// never strand a user. Ids from earlier catalogs are remapped to their successor.
    func modelID(for provider: AIProvider) -> String {
        guard let stored = modelIDs[provider.rawValue], !stored.isEmpty else {
            return provider.defaultModelID
        }
        return AIProvider.retiredModelIDs[stored] ?? stored
    }

    /// Whether the effective model is a hand-typed id rather than a catalog entry.
    func usesCustomModelID(for provider: AIProvider) -> Bool {
        provider.model(withID: modelID(for: provider)) == nil
    }

    func setModelID(_ id: String, for provider: AIProvider) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        modelIDs[provider.rawValue] = trimmed
        defaults.set(modelIDs, forKey: Key.modelIDs)
        objectWillChange.send()
    }

    /// Re-reads things that can change without a Settings edit, such as Apple
    /// Intelligence finishing its model download. Cheap; call when a screen appears.
    func refreshProviderAvailability() {
        recomputeConfiguredProviders()
        if !AIProvider.allCases.contains(selectedProvider) { selectedProvider = .anthropic }
    }

    // MARK: Internals

    private func recomputeConfiguredProviders() {
        configuredProviders = Set(AIProvider.allCases.filter(isUsable))
    }

    private func refreshKeyCache() {
        for provider in AIProvider.allCases where provider != .apple {
            keyCache[provider] = Keychain.read(service: keychainService, account: provider.rawValue)
        }
        recomputeConfiguredProviders()
    }

    /// One-time move of the pre-1.0 `ANTHROPIC_API_KEY` UserDefaults entry into the Keychain.
    private func migrateLegacyAnthropicKeyIfNeeded() {
        guard !defaults.bool(forKey: Key.didMigrateLegacyKey) else { return }

        let legacy = (defaults.string(forKey: Constants.legacyAnthropicDefaultsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else {
            defaults.removeObject(forKey: Constants.legacyAnthropicDefaultsKey)
            defaults.set(true, forKey: Key.didMigrateLegacyKey)
            return
        }

        let existing = Keychain.read(service: keychainService, account: AIProvider.anthropic.rawValue)
        if existing == nil {
            guard Keychain.write(legacy,
                                 service: keychainService,
                                 account: AIProvider.anthropic.rawValue) else {
                // Keychain unavailable (e.g. locked). Leave the old value in place
                // and stay unmigrated so the next launch retries.
                return
            }
        }
        defaults.removeObject(forKey: Constants.legacyAnthropicDefaultsKey)
        defaults.set(true, forKey: Key.didMigrateLegacyKey)
    }
}
