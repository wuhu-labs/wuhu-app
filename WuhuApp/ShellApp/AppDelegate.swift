import AppKit
import SwiftUI
import ComposableArchitecture

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private let store = Store(initialState: AppFeature.State()) {
    AppFeature()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1200, height: 750),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )

    // Chrome-less setup — done once, at creation.
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = .clear
    window.isMovableByWindowBackground = true
    window.setFrameAutosaveName("WuhuMacShell")
    window.minSize = NSSize(width: 960, height: 640)
    window.center()

    // Host the SwiftUI shell.
    let hostingView = NSHostingView(rootView: MacAppShell(store: store))
    window.contentView = hostingView

    window.makeKeyAndOrderFront(nil)
    self.window = window

    // Push traffic lights down to make room for the nav row.
    setupTrafficLightConstraints(in: window)
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  // MARK: - Traffic Light Positioning

  /// Uses Auto Layout to pin the traffic light buttons' container to
  /// a fixed vertical offset from the top of the titlebar. This
  /// survives resizes, full-screen transitions, and tab bar changes
  /// without needing notification observers or frame hacking.
  private func setupTrafficLightConstraints(in window: NSWindow) {
    guard let close = window.standardWindowButton(.closeButton),
          let container = close.superview
    else { return }

    let topInset = PanelMetrics.trafficLightInset

    // The container is the "NSTitlebarContainerView" superview's child
    // that holds all three buttons. We pin it via Auto Layout.
    container.translatesAutoresizingMaskIntoConstraints = false

    if let titlebarContainer = container.superview {
      NSLayoutConstraint.activate([
        container.topAnchor.constraint(
          equalTo: titlebarContainer.topAnchor,
          constant: topInset
        ),
        container.leadingAnchor.constraint(
          equalTo: titlebarContainer.leadingAnchor
        ),
      ])
    }
  }
}
