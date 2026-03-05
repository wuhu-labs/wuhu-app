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
    window.toolbar = nil

    // Host the SwiftUI shell.
    let hostingView = NSHostingView(rootView: MacAppShell(store: store))
    hostingView.frame = window.contentView!.bounds
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView

    window.makeKeyAndOrderFront(nil)
    self.window = window

    // Debug: print titlebar geometry
    if let close = window.standardWindowButton(.closeButton),
       let container = close.superview,
       let titlebarView = container.superview,
       let titlebarContainer = titlebarView.superview {
      print("titlebarContainer frame:", titlebarContainer.frame)
      print("titlebarView frame:", titlebarView.frame)
      print("button container frame:", container.frame)
      print("close button frame:", close.frame)
      print("window frame height:", window.frame.height)
      print("contentView frame:", window.contentView?.frame ?? .zero)
      print("contentLayoutRect:", window.contentLayoutRect)
      // How much space the titlebar takes:
      let titlebarHeight = window.frame.height - window.contentLayoutRect.height
      print("titlebar height:", titlebarHeight)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
