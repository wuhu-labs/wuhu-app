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

    // Chrome-less setup — done once, at creation, no hacks needed.
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = .clear
    window.isMovableByWindowBackground = true
    window.setFrameAutosaveName("WuhuMacShell")
    window.minSize = NSSize(width: 960, height: 640)
    window.center()

    // Host the SwiftUI shell as the window's content.
    let hostingView = NSHostingView(rootView: MacAppShell(store: store))
    window.contentView = hostingView

    window.makeKeyAndOrderFront(nil)
    self.window = window

    // Reposition traffic lights now and on every resize.
    repositionTrafficLights()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize(_:)),
      name: NSWindow.didResizeNotification,
      object: window
    )
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  // MARK: - Traffic Light Positioning

  @objc private func windowDidResize(_ notification: Notification) {
    repositionTrafficLights()
  }

  private func repositionTrafficLights() {
    guard let window else { return }
    let topInset: CGFloat = PanelMetrics.trafficLightInset
    let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for type in types {
      guard let button = window.standardWindowButton(type),
            let container = button.superview
      else { continue }
      var frame = container.frame
      frame.origin.y = window.frame.height - frame.height - topInset
      container.frame = frame
    }
  }
}
