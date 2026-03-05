import AppKit
import SwiftUI
import ComposableArchitecture

// ┌─────────────────────────────────────────────────────────────────┐
// │  AppDelegate — AppKit lifecycle for the macOS shell             │
// │                                                                 │
// │  Why AppKit lifecycle instead of SwiftUI App?                   │
// │  SwiftUI's WindowGroup creates the NSWindow before we can       │
// │  configure it. By owning the NSWindow ourselves, we set the     │
// │  style mask, titlebar transparency, and toolbar at creation     │
// │  time — no post-hoc NSViewRepresentable hacks needed.           │
// │                                                                 │
// │  Traffic light positioning strategy (Option 2):                 │
// │  We use an empty NSToolbar with .unified style to get a         │
// │  taller titlebar (~52pt vs default 32pt). The traffic light     │
// │  buttons auto-center vertically in the taller titlebar.         │
// │  This is the same approach Arc, Things, Linear, and Notion      │
// │  use. Apple-sanctioned, survives fullscreen/tabs/resizes        │
// │  without frame hacking or notification observers.               │
// │                                                                 │
// │  Alternative approaches considered:                             │
// │  1. AutoLayout on traffic light container — maximum design      │
// │     flexibility but requires re-applying on fullscreen/tab      │
// │     changes as Apple resets frames.                              │
// │  2. Design around default 32pt titlebar — simplest but          │
// │     less room for a nav row with back/forward buttons.          │
// │  3. Hide traffic lights and draw custom — Electron-app          │
// │     territory, not worth it for native.                         │
// │                                                                 │
// │  Titlebar geometry (for reference):                             │
// │  With .unified toolbar:                                         │
// │    titlebarContainer: full window frame (overlay)               │
// │    titlebarView: ~52pt strip at top of window                   │
// │    Traffic lights auto-centered in that strip                   │
// │    contentLayoutRect starts ~52pt below window top               │
// │  With fullSizeContentView, SwiftUI content extends behind       │
// │  the titlebar — the background material fills the whole         │
// │  window, and the nav row aligns with the traffic lights.        │
// └─────────────────────────────────────────────────────────────────┘

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

    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.backgroundColor = .clear
    window.isMovableByWindowBackground = true
    window.setFrameAutosaveName("WuhuMacShell")
    window.minSize = NSSize(width: 960, height: 640)
    window.center()

    // Empty toolbar with .unified style creates a taller titlebar
    // (~52pt). Traffic lights auto-center in this space, giving
    // room for a nav row (sidebar toggle, back/forward) alongside.
    let toolbar = NSToolbar(identifier: "MainToolbar")
    toolbar.showsBaselineSeparator = false
    toolbar.displayMode = .iconOnly
    window.toolbar = toolbar
    window.toolbarStyle = .unified

    // Host the SwiftUI shell.
    let hostingView = NSHostingView(rootView: MacAppShell(store: store))
    hostingView.frame = window.contentView!.bounds
    hostingView.autoresizingMask = [.width, .height]
    window.contentView = hostingView

    window.makeKeyAndOrderFront(nil)
    self.window = window

    // Debug: print geometry so we can tune PanelMetrics
    if let close = window.standardWindowButton(.closeButton) {
      let titlebarHeight = window.frame.height - window.contentLayoutRect.height
      print("titlebar height:", titlebarHeight)
      print("close button frame:", close.frame)
      print("close button superview frame:", close.superview?.frame ?? .zero)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }
}
