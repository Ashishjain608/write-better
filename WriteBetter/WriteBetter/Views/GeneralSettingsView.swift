import AppKit
import SwiftUI

/// General tab (§7.2). Shortcut, capture, and app-level preferences.
struct GeneralSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var accessibility = AccessibilityManager.shared
    @ObservedObject private var hotkey = HotkeyManager.shared

    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system
    @AppStorage("reduceVisualEffects") private var reduceVisualEffects = false

    @State private var launchAtLoginError: String?

    var body: some View {
        SettingsPane {
            shortcutGroup
            captureGroup
            appGroup
        }
        // §9.3 rule 5 — the API returns a stale value, so poll while this pane is up.
        .onAppear { accessibility.beginPolling() }
        .onDisappear { accessibility.endPolling() }
    }

    // MARK: Shortcut

    private var shortcutGroup: some View {
        SettingsGroup("Shortcut") {
            SettingsRow("Improve text",
                        subtitle: hotkey.registrationFailed
                            ? "\(HotkeyManager.displayString) is taken by another app."
                            : "Custom shortcuts are coming in a later release.") {
                HStack(spacing: Theme.Space.xs) {
                    if hotkey.registrationFailed {
                        Button("Retry") { hotkey.retry() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    ForEach(HotkeyManager.displayKeys, id: \.self) { Keycap(symbol: $0) }
                }
                .accessibilityElement(children: hotkey.registrationFailed ? .contain : .ignore)
                .accessibilityLabel("Shift Command Space")
            }
        }
    }

    // MARK: Capture

    private var captureGroup: some View {
        SettingsGroup("Capture") {
            SettingsRow("Use the current selection",
                        subtitle: "Reads selected text instead of the clipboard.") {
                Toggle("", isOn: $settings.autoCaptureSelection)
                    .toggleStyle(.switch)
                    .tint(Theme.Color.accent)
                    .labelsHidden()
                    .accessibilityLabel("Use the current selection")
            }

            if !accessibility.isSandboxed {
                SettingsDivider()
                accessibilityRow
            }
        }
    }

    @ViewBuilder
    private var accessibilityRow: some View {
        if accessibility.isTrusted {
            // Granted: one line, and an off-switch that only stops *our* use of it —
            // we cannot revoke the TCC grant.
            SettingsRow("Replace in place is on",
                        subtitle: "WriteBetter can read your selection and paste results back.") {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Color.success)
            }
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack(alignment: .top, spacing: Theme.Space.lg) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Color.warning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                        Text("Accessibility access needed").textStyle(.label)
                        Text("""
                             Lets WriteBetter read your selection and paste the result \
                             back. Everything else works without it.
                             """)
                            .textStyle(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Theme.Space.lg)
                    // The ONLY place that may prompt — a direct user click (§9.3 rule 1).
                    Button("Grant…") { accessibility.requestAccess() }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityLabel("Grant Accessibility access")
                }
                HStack {
                    Spacer(minLength: 0)
                    Button("Open System Settings") { accessibility.openSystemSettings() }
                        .buttonStyle(.link)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.accentText)
                }
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.lg)
        }
    }

    // MARK: App

    private var appGroup: some View {
        SettingsGroup("App") {
            SettingsRow("Launch at login") {
                Toggle("", isOn: launchAtLoginBinding)
                    .toggleStyle(.switch)
                    .tint(Theme.Color.accent)
                    .labelsHidden()
                    .accessibilityLabel("Launch at login")
            }

            if let launchAtLoginError {
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Color.danger)
                        .accessibilityHidden(true)
                    Text(launchAtLoginError)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Color.danger)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.md)
            }

            SettingsDivider()

            SettingsRow("Appearance") {
                Picker("", selection: $appearance) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 140)
                .accessibilityLabel("Appearance")
                .onChange(of: appearance) { _, newValue in newValue.apply() }
            }

            SettingsDivider()

            SettingsRow("Reduce visual effects",
                        subtitle: "Uses an opaque panel instead of the blurred one.") {
                Toggle("", isOn: $reduceVisualEffects)
                    .toggleStyle(.switch)
                    .tint(Theme.Color.accent)
                    .labelsHidden()
                    .accessibilityLabel("Reduce visual effects")
            }
        }
    }

    /// Writes the persisted flag, performs the `SMAppService` registration, and on
    /// failure reverts the toggle and surfaces the reason instead of swallowing it.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLoginManager.apply(newValue)
                    settings.launchAtLogin = newValue
                    launchAtLoginError = nil
                } catch {
                    settings.launchAtLogin = LaunchAtLoginManager.isRegistered
                    launchAtLoginError = LaunchAtLoginManager.explain(error)
                }
            }
        )
    }
}

// MARK: - Appearance preference

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, dark, light

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .dark:   return "Dark"
        case .light:  return "Light"
        }
    }

    /// Applied app-wide so the panel, Settings and Welcome all agree.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    @MainActor
    static var current: AppearancePreference {
        let raw = UserDefaults.standard.string(forKey: "appearancePreference") ?? ""
        return AppearancePreference(rawValue: raw) ?? .system
    }
}

#Preview("General") {
    GeneralSettingsView(settings: .shared)
        .frame(width: 560, height: 620)
}
