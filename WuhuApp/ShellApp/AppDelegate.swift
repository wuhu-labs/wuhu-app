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

    // Make the titlebar area part of the content — this lets SwiftUI
    // draw behind the titlebar, with traffic lights floating on top.
    window.toolbar = nil

    // Host the SwiftUI shell.
    let hostingView = NSHostingView(rootView: MacAppShell(store: store))
    hostingView.frame = window.contentView!.bounds
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView

    window.makeKeyAndOrderFront(nil)
    self.window = window

    // Push traffic lights down to align with the nav row.
    repositionTrafficLights()

    // Re-position on resize — the system resets them.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize(_:)),
      name: NSWindow.didResizeNotification,
      object: window
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidResize(_:)),
      name: NSWindow.didEndLiveResizeNotification,
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

    // The traffic light buttons are inside an NSTitlebarContainerView
    // → NSTitlebarView → button container. We need to find the
    // button container (direct superview of the close button) and
    // move it down.
    guard let close = window.standardWindowButton(.closeButton),
          let container = close.superview
    else { return }

    // The container's coordinate system: origin is bottom-left within
    // its superview (the NSTitlebarView). Moving origin.y DOWN means
    // a SMALLER value (further from top). But the titlebar view itself
    // is flipped, so... let's just measure and set explicitly.
    //
    // We want the traffic lights centered vertically in the nav row.
    // Nav row height = 38pt, traffic light button height ≈ 14pt.
    // So center = (38 - 14) / 2 = 12pt from top of nav row.
    // The nav row starts at the top of the window content.
    //
    // The titlebar container is positioned relative to the top of
    // the window. Default position puts buttons at ~4pt from top.
    // We want them at ~12pt from top (vertically centered in 38pt row).

    // Simply adjust the y position of each button within its container.
    let desiredCenterY: CGFloat = PanelMetrics.navRowHeight / 2

    let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for type in types {
      guard let button = window.standardWindowButton(type) else { continue }
      let buttonHeight = button.frame.height
      var buttonFrame = button.frame
      // In the container's coordinate system (non-flipped), higher y = higher on screen.
      // We want the button centered at desiredCenterY from the top of the window.
      // The container sits at some y in the titlebar. We just center the button
      // within the container, then let the container positioning handle the rest.
      buttonFrame.origin.y = (button.superview!.frame.height - buttonHeight) / 2
      button.frame = buttonFrame
    }

    // Now move the whole container down.
    // The container's superview uses flipped coordinates (top = 0).
    if let titlebarView = container.superview {
      var containerFrame = container.frame
      // In flipped coords: origin.y = distance from top.
      // We want the center of the container at navRowHeight/2 from the top.
      let containerCenter = PanelMetrics.navRowHeight / 2
      containerFrame.origin.y = containerCenter - containerFrame.height / 2
      container.frame = containerFrame

      // Debug output
      print("titlebar flipped:", titlebarView.isFlipped)
      print("container frame:", container.frame)
      print("close button frame:", close.frame)
    }
  }
}
