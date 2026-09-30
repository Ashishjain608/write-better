import Combine
import Sparkle
import SwiftUI

/// Sparkle 2 auto-update. The feed URL, the EdDSA public key and the
/// automatic-check default live in Info.plist (`SUFeedURL`, `SUPublicEDKey`,
/// `SUEnableAutomaticChecks`); this only owns the controller and exposes the two
/// things the UI needs.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// False while a check is already running, so the menu item greys out.
    @Published private(set) var canCheckForUpdates = false

    private let controller = SPUStandardUpdaterController(startingUpdater: false,
                                                          updaterDelegate: nil,
                                                          userDriverDelegate: nil)

    private init() {
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Called once from `applicationDidFinishLaunching`, after the `--self-check`
    /// exit, so the self-check never touches the network.
    func start() {
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// Persisted by Sparkle in the app's defaults (`SUEnableAutomaticChecks`).
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
        }
    }
}

/// "Check for Updates…". A view of its own so the disabled state tracks
/// `canCheckForUpdates` inside an `NSMenu` (Sparkle's documented SwiftUI pattern).
struct CheckForUpdatesButton: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Button {
            updater.checkForUpdates()
        } label: {
            Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
