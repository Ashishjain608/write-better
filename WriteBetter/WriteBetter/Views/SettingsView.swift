import SwiftUI

/// The real macOS settings window (§7.2).
///
/// A `TabView` inside SwiftUI's `Settings` scene automatically picks up the
/// system's settings toolbar style with centred tabs — the HIG explicitly says not
/// to hand-roll a lookalike. The last-viewed tab is restored on reopen, and there
/// is no Save button: everything applies immediately.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var router: SettingsRouter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $router.tab) {
            ProvidersSettingsView(settings: settings, router: router)
                .tabItem { Label(SettingsRouter.Tab.providers.title,
                                 systemImage: SettingsRouter.Tab.providers.icon) }
                .tag(SettingsRouter.Tab.providers)

            ActionsSettingsView()
                .tabItem { Label(SettingsRouter.Tab.actions.title,
                                 systemImage: SettingsRouter.Tab.actions.icon) }
                .tag(SettingsRouter.Tab.actions)

            GeneralSettingsView(settings: settings)
                .tabItem { Label(SettingsRouter.Tab.general.title,
                                 systemImage: SettingsRouter.Tab.general.icon) }
                .tag(SettingsRouter.Tab.general)

            AboutSettingsView(settings: settings)
                .tabItem { Label(SettingsRouter.Tab.about.title,
                                 systemImage: SettingsRouter.Tab.about.icon) }
                .tag(SettingsRouter.Tab.about)
        }
        .frame(width: 560)
        .frame(minHeight: 560, idealHeight: 620, maxHeight: 760)
        .background(Theme.Color.surface)
        // M21 — the tab change is a cross-fade.
        .animation(Theme.Motion.curve(.easeInOut(duration: 0.15), reduceMotion: reduceMotion),
                   value: router.tab)
    }
}

/// Shared chrome for a settings pane: 24pt horizontal / 20pt vertical inset, scrolling.
struct SettingsPane<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.h1)
            .padding(.vertical, Theme.Space.xxl)
        }
        .background(Theme.Color.surface)
    }
}

/// A titled group of rows — the shape every settings section uses.
struct SettingsGroup<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            SectionHeader(title)
            VStack(spacing: 0) { content }
                .cardSurface()
        }
    }
}

/// One 36pt (or 44pt with a subtitle) row inside a `SettingsGroup`.
struct SettingsRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text(title).textStyle(.label)
                if let subtitle {
                    Text(subtitle)
                        .textStyle(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Theme.Space.lg)
            trailing
        }
        .padding(.horizontal, Theme.Space.lg)
        .frame(minHeight: subtitle == nil ? 36 : 44)
        .padding(.vertical, subtitle == nil ? 0 : Theme.Space.md)
    }
}

/// A hairline between rows in a group.
struct SettingsDivider: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Rectangle()
            .fill(Theme.Color.stroke(reduceTransparency: reduceTransparency))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

#Preview("Settings") {
    SettingsView(settings: .shared, router: SettingsRouter())
}
