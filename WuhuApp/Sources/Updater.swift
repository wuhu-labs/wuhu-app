#if os(macOS)
import Sparkle
import SwiftUI

/// Lightweight wrapper around Sparkle's updater controller.
///
/// Create a single instance at app launch and keep it alive for the
/// lifetime of the process. Sparkle handles periodic background checks
/// automatically once `startingUpdater: true` is passed.
@MainActor
final class SoftwareUpdater: ObservableObject {
  let controller: SPUStandardUpdaterController

  /// Whether the "Check for Updates…" button should be enabled.
  /// Sparkle disables it while a check is already in progress.
  @Published var canCheckForUpdates = false

  init() {
    controller = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )

    // Observe Sparkle's canCheckForUpdates KVO property and republish
    // it as a Combine value so SwiftUI can bind to it.
    controller.updater.publisher(for: \.canCheckForUpdates)
      .assign(to: &$canCheckForUpdates)
  }

  func checkForUpdates() {
    controller.updater.checkForUpdates()
  }
}

/// A menu-bar command that adds "Check for Updates…" under the app menu.
struct CheckForUpdatesCommand: Commands {
  @ObservedObject var updater: SoftwareUpdater

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Check for Updates…") {
        updater.checkForUpdates()
      }
      .disabled(!updater.canCheckForUpdates)
    }
  }
}
#endif
