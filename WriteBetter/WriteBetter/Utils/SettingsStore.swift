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

    /// Providers that currently hold a usable key.
    @Published private(set) var configuredProviders: Set<AIProvider> = []

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
        self.selectedProvider = storedProvider.flatMap(AIProvider.init(rawValue:)) ?? .anthropic
        self.modelIDs = defaults.dictionary(forKey: Key.modelIDs) as? [String: String] ?? [:]
        self.autoCaptureSelection = defaults.bool(forKey: Key.autoCaptureSelection)
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)

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

    /// The selected provider has a usable key.
    var isConfigured: Bool { hasKey(for: selectedProvider) }

    // MARK: Model selection

    /// Persisted model for a provider; falls back to `provider.models[0].id`
    /// (also when a previously stored id has been retired from the catalog).
    func modelID(for provider: AIProvider) -> String {
        guard let stored = modelIDs[provider.rawValue],
              provider.model(withID: stored) != nil
        else { return provider.defaultModelID }
        return stored
    }

    func setModelID(_ id: String, for provider: AIProvider) {
        guard provider.model(withID: id) != nil else { return }
        modelIDs[provider.rawValue] = id
        defaults.set(modelIDs, forKey: Key.modelIDs)
        objectWillChange.send()
    }

    // MARK: Internals

    private func recomputeConfiguredProviders() {
        configuredProviders = Set(AIProvider.allCases.filter { !(keyCache[$0] ?? "").isEmpty })
    }

    private func refreshKeyCache() {
        for provider in AIProvider.allCases {
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
