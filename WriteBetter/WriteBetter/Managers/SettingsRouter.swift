import AppKit
import Combine
import SwiftUI

/// Which Settings pane is showing, and which provider row should be open when it
/// appears. The last-viewed tab is restored on reopen, per HIG.
@MainActor
final class SettingsRouter: ObservableObject {

    static let shared = SettingsRouter()

    enum Tab: String, CaseIterable, Identifiable {
        case providers, general, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .providers: return "Providers"
            case .general:   return "General"
            case .about:     return "About"
            }
        }

        var icon: String {
            switch self {
            case .providers: return "key.fill"
            case .general:   return "gearshape"
            case .about:     return "info.circle"
            }
        }
    }

    private static let lastTabKey = "settingsLastTab"

    @Published var tab: Tab {
        didSet {
            guard tab != oldValue else { return }
            UserDefaults.standard.set(tab.rawValue, forKey: Self.lastTabKey)
        }
    }

    /// The provider row that should be expanded (and whose key field should focus).
    @Published var expandedProvider: AIProvider?
    /// Bumped to re-trigger focus even when `expandedProvider` is unchanged.
    @Published var focusRequest: Int = 0

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.lastTabKey)
        tab = stored.flatMap(Tab.init(rawValue:)) ?? .providers
        expandedProvider = SettingsStore.shared.selectedProvider
    }

    /// Brings the Settings scene forward, optionally deep-linked to a provider row.
    ///
    /// With `LSUIElement` set, the Settings window opens *behind* other apps unless
    /// we activate first (§11.2 pitfall 10).
    func open(tab requestedTab: Tab? = nil, provider: AIProvider? = nil) {
        if let requestedTab { tab = requestedTab }
        if let provider {
            tab = .providers
            expandedProvider = provider
            focusRequest &+= 1
        }

        NSApp.activate(ignoringOtherApps: true)

        // macOS 14 renamed the selector; try the new one, then the old.
        let selectors = [Selector(("showSettingsWindow:")), Selector(("showPreferencesWindow:"))]
        for selector in selectors where NSApp.sendAction(selector, to: nil, from: nil) {
            return
        }
    }
}
