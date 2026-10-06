import AppKit
import Combine
import SwiftUI

/// Which Settings pane is showing, and which provider row should be open when it
/// appears. The last-viewed tab is restored on reopen, per HIG.
@MainActor
final class SettingsRouter: ObservableObject {

    static let shared = SettingsRouter()

    enum Tab: String, CaseIterable, Identifiable {
        case providers, actions, general, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .providers: return "Providers"
            case .actions:   return "Actions"
            case .general:   return "General"
            case .about:     return "About"
            }
        }

        var icon: String {
            switch self {
            case .providers: return "key.fill"
            case .actions:   return "bolt"
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
        openSettings?()
    }

    /// SwiftUI's opener, handed over by `SettingsOpenerBridge`. Since macOS 14 it is
    /// the only way to open the Settings scene: `showSettingsWindow:` is ignored.
    var openSettings: OpenSettingsAction?
}

/// Captures `openSettings` from the scene's environment so AppKit callers can use it.
struct SettingsOpenerBridge: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear { SettingsRouter.shared.openSettings = openSettings }
    }
}
