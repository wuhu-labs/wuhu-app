#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Window Corner Radius Environment

/// The window corner radius, used to compute concentric inner radii for
/// panel islands. On macOS 26 Tahoe the system window radius is ~10pt.
///
/// This is manually set for now. In the future we can read it from the
/// NSWindow or the display corner curve.
///
/// Inner panel radius = windowCornerRadius − panelInset
///
/// Usage:
///   @Environment(\.windowCornerRadius) var windowCornerRadius
private struct WindowCornerRadiusKey: EnvironmentKey {
  static let defaultValue: CGFloat = 10
}

extension EnvironmentValues {
  var windowCornerRadius: CGFloat {
    get { self[WindowCornerRadiusKey.self] }
    set { self[WindowCornerRadiusKey.self] = newValue }
  }
}

// MARK: - Window Configurator

/// An invisible NSView that configures its hosting NSWindow for
/// an Arc-style chrome-less layout once it's added to the hierarchy.
///
/// Handles:
/// - Transparent title bar with content extending behind it
/// - Hidden title text
/// - Full-size content view
/// - Traffic lights repositioned downward
/// - Window draggable by background
///
/// Traffic lights are repositioned on layout via `layout()` override
/// so they stay correct across resizes without NotificationCenter.
@MainActor
struct WindowConfigurator: NSViewRepresentable {
  var trafficLightTopInset: CGFloat = 14

  func makeNSView(context: Context) -> NSView {
    WindowConfiguratorView(topInset: trafficLightTopInset)
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private final class WindowConfiguratorView: NSView {
  private let topInset: CGFloat
  private var configured = false

  init(topInset: CGFloat) {
    self.topInset = topInset
    super.init(frame: .zero)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError() }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window, !configured else { return }
    configured = true

    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.styleMask.insert(.fullSizeContentView)
    window.backgroundColor = .clear
    window.isMovableByWindowBackground = true

    repositionTrafficLights()
  }

  // Called on every layout pass — keeps traffic lights positioned
  // across resizes, full-screen transitions, etc.
  override func layout() {
    super.layout()
    repositionTrafficLights()
  }

  private func repositionTrafficLights() {
    guard let window else { return }
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

// MARK: - Vibrancy Background

/// Full-window `NSVisualEffectView` with sidebar material and behind-window
/// blending. This is the "sea" that the panel islands float on.
///
/// An optional tint color is composited on top as a sublayer so the
/// vibrancy / blur effect is preserved.
struct SidebarMaterialBackground: NSViewRepresentable {
  var tintColor: NSColor?
  var tintOpacity: CGFloat = 0.06

  func makeNSView(context: Context) -> NSVisualEffectView {
    let effect = NSVisualEffectView()
    effect.material = .sidebar
    effect.blendingMode = .behindWindow
    effect.state = .active

    if let tint = tintColor {
      let overlay = NSView()
      overlay.wantsLayer = true
      overlay.layer?.backgroundColor = tint.withAlphaComponent(tintOpacity).cgColor
      overlay.translatesAutoresizingMaskIntoConstraints = false
      effect.addSubview(overlay)
      NSLayoutConstraint.activate([
        overlay.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
        overlay.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
        overlay.topAnchor.constraint(equalTo: effect.topAnchor),
        overlay.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
      ])
    }

    return effect
  }

  func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - View Extension

extension View {
  /// Configures the hosting NSWindow for an Arc-style chrome-less layout.
  func windowChrome(trafficLightTopInset: CGFloat = 14) -> some View {
    background(
      WindowConfigurator(trafficLightTopInset: trafficLightTopInset)
        .frame(width: 0, height: 0)
    )
  }
}
#endif
