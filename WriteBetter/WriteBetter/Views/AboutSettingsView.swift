import AppKit
import SwiftUI

/// About tab (§7.2) — the mark, the version, the privacy promise, and a reset.
struct AboutSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var updater = Updater.shared

    @State private var sheet: Sheet?
    @State private var showResetConfirmation = false

    enum Sheet: String, Identifiable {
        case shortcuts, privacy
        var id: String { rawValue }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: Theme.Space.lg) {
            Spacer(minLength: Theme.Space.h2)

            BrandMark(size: 64)
            Wordmark(size: 22)

            Text(versionString)
                .textStyle(.caption)
                .monospacedDigit()

            CheckForUpdatesButton()
                .buttonStyle(SecondaryButtonStyle())

            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
                .toggleStyle(.checkbox)
                .textStyle(.caption)

            Spacer().frame(height: Theme.Space.lg)

            HStack(spacing: Theme.Space.lg) {
                Button("Keyboard Shortcuts") { sheet = .shortcuts }
                    .buttonStyle(SecondaryButtonStyle())
                Button("Privacy") { sheet = .privacy }
                    .buttonStyle(SecondaryButtonStyle())
                Button {
                    NSWorkspace.shared.open(settings.selectedProvider.consoleURL)
                } label: {
                    Label("Provider console", systemImage: "arrow.up.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }

            Spacer(minLength: Theme.Space.h2)

            Text("Your text is sent only to the provider you choose. Keys stay in your Mac's Keychain.")
                .textStyle(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.h2)

            Button(showResetConfirmation ? "Tap again to confirm" : "Reset all settings") {
                if showResetConfirmation {
                    resetEverything()
                    showResetConfirmation = false
                } else {
                    showResetConfirmation = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { showResetConfirmation = false }
                }
            }
            .buttonStyle(.plain)
            .textStyle(.caption)
            .foregroundStyle(Theme.Color.danger.opacity(0.8))
            .minimumHitTarget()
            .help("Removes every API key and preference")
            .accessibilityLabel("Reset all settings")
            .accessibilityHint("Removes every API key and preference. Press twice to confirm.")

            Spacer(minLength: Theme.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Color.surface)
        .sheet(item: $sheet) { which in
            switch which {
            case .shortcuts: shortcutsSheet
            case .privacy:   privacySheet
            }
        }
    }

    private var shortcutsSheet: some View {
        ShortcutsOverlay(isPresented: Binding(get: { sheet == .shortcuts },
                                              set: { if !$0 { sheet = nil } }))
            .frame(width: 480, height: 460)
    }

    private var privacySheet: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Privacy").textStyle(.title)
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                bullet("Your text is sent to the provider you select, and to nobody else.")
                bullet("API keys are stored in the macOS Keychain, never in a file and never in a log.")
                bullet("WriteBetter has no analytics, no telemetry and no account.")
                bullet("Update checks download a feed from GitHub Releases, at most once a day, and send nothing about you. Turn them off in About.")
                bullet("Accessibility access is optional, and is used only to read your selection and paste a result back.")
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { sheet = nil }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(Theme.Space.h1)
        .frame(width: 460, height: 320)
        .background(Theme.Color.surface)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            Circle()
                .fill(Theme.Color.accent)
                .frame(width: 4, height: 4)
                .padding(.top, 6)
                .accessibilityHidden(true)
            Text(text)
                .textStyle(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resetEverything() {
        for provider in AIProvider.allCases {
            settings.setAPIKey("", for: provider)
        }
        settings.customBaseURL = ""
        settings.autoCaptureSelection = false
        settings.launchAtLogin = false
        try? LaunchAtLoginManager.apply(false)
        settings.selectedProvider = AIProvider.allCases.first ?? settings.selectedProvider
        UserDefaults.standard.removeObject(forKey: "appearancePreference")
        UserDefaults.standard.removeObject(forKey: "reduceVisualEffects")
        UserDefaults.standard.removeObject(forKey: "settingsLastTab")
        UserDefaults.standard.removeObject(forKey: WelcomeWindowController.hasSeenWelcomeKey)
        AppearancePreference.system.apply()
    }
}

#Preview("About") {
    AboutSettingsView(settings: .shared)
        .frame(width: 560, height: 620)
}
