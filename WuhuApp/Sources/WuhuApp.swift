import ComposableArchitecture
import SwiftUI

// MARK: - Entry Point

@main
struct WuhuApp: App {
  #if os(macOS)
  @StateObject private var updater = SoftwareUpdater()
  #endif

  var body: some Scene {
    WindowGroup {
      AppView(
        store: Store(initialState: AppFeature.State()) {
          AppFeature()
        }
      )
    }
    #if os(macOS)
    // Use default window style so the titlebar container (with traffic
    // lights) exists. WindowConfigurator makes the titlebar transparent
    // and extends content behind it via NSWindow configuration.
    .defaultSize(width: 1200, height: 750)
    .commands {
      CheckForUpdatesCommand(updater: updater)
    }
    #endif

    #if os(macOS)
      Settings {
        SettingsView(
          workspaces: WorkspaceStorage.loadWorkspaces(),
          activeWorkspace: {
            let ws = WorkspaceStorage.loadWorkspaces()
            let id = WorkspaceStorage.loadActiveWorkspaceID()
            return ws.first(where: { $0.id == id }) ?? ws.first ?? .default
          }(),
          onSwitchWorkspace: nil
        )
      }
    #endif
  }
}
