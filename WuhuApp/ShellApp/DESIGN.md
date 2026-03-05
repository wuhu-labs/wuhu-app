# WuhuMacShell — Design Notes

## Tri-Panel Layout

Arc Browser-style layout with three independent columns:

```
┌─────────┬────────────┬──────────────────────────────────┐
│ traffic │            │                                  │
│ lights  │            │                                  │
│ ⊞ ← → ↻ │            │                                  │
│         │  Secondary │         Primary Content          │
│ Sidebar │   Panel    │          (session, doc,          │
│ (clear) │  (island)  │           chat, etc.)            │
│         │            │           (island)               │
│         │            │                                  │
│  + ↻    │            │                                  │
└─────────┴────────────┴──────────────────────────────────┘
```

### Column 1 — Sidebar (transparent)
- No background — sits on the window's vibrancy material.
- Contains: workspace switcher, tab buttons (Docs, Messages, Agents/Settings
  placeholders), collapsible Sessions section with Inbox + Add Folder.
- **Controls column 2 only.** Does NOT control column 3.
- Width: 200pt.

### Column 2 — Secondary Panel (opaque island)
- Rounded corners, `windowBackgroundColor`.
- Content switches based on sidebar selection: doc tree, message channel
  list, or session list.
- Has a hide button (×). Can be toggled via sidebar toggle.
- Width: 280pt.

### Column 3 — Primary Content (opaque island)
- Left corners: concentric radius (`windowCornerRadius - inset`).
- Right side: flush with window edge (0 radius — OS handles window rounding).
- Independent of sidebar state — shows session detail, doc viewer, or chat.
- Fills remaining width.

### Panel Metrics
- `inset = 6pt` — gap between window edge and panel islands.
- `gap = 1pt` — gap between adjacent panels.
- Panel corner radius = `windowCornerRadius - inset` (concentric with window).
- `windowCornerRadius` is an environment value, default 10pt.

## Window Chrome

### AppKit Lifecycle
We use `NSApplicationDelegate` + manual `NSWindow` creation instead of
SwiftUI's `App` protocol. This gives us complete control over the window
configuration at creation time — no post-hoc `NSViewRepresentable` hacks.

### Titlebar Strategy (Option 2 — Empty NSToolbar)
An empty `NSToolbar` with `.unified` style creates a taller titlebar (~52pt
vs default 32pt). The traffic light buttons auto-center in this space.

This is the same approach Arc, Things, Linear, and Notion use. It's
Apple-sanctioned and survives fullscreen, tab changes, and resizes without
any frame hacking or notification observers.

#### Alternatives Considered
1. **AutoLayout on traffic light container** — maximum design flexibility.
   We measured the view hierarchy: `titlebarContainer → titlebarView →
   buttonContainer → buttons`. The titlebarView is non-flipped, sits at
   `y = windowHeight - 32` in window coords. Could constrain the container's
   `topAnchor`. Risk: Apple resets frames on fullscreen/tab changes.
2. **Design around default 32pt titlebar** — simplest, zero AppKit code.
   Less "Arc-like" since the nav row has very little vertical space.
3. **Hide traffic lights and draw custom** — Electron-app territory. Maximum
   control but fighting the platform.

### Titlebar Geometry Reference
```
With .unified toolbar (~52pt titlebar):
  titlebarContainer: full window frame (overlay, non-flipped)
  titlebarView: ~52pt strip at top of window
  buttonContainer: fills titlebarView
  traffic lights: auto-centered vertically

With default titlebar (32pt, for reference):
  titlebarContainer: (0, 0, W, H) — full window
  titlebarView: (0, H-32, W, 32)
  buttonContainer: (0, 0, W, 32) — fills titlebarView
  close button: (9, 9, 14, 14) — centered in 32pt

contentLayoutRect: starts below titlebar
fullSizeContentView: SwiftUI content extends behind titlebar
```

### Window Configuration
```swift
styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
titlebarAppearsTransparent = true
titleVisibility = .hidden
backgroundColor = .clear
isMovableByWindowBackground = true
toolbarStyle = .unified  // creates taller titlebar
```

## Future: Portal-Based Panel Architecture

When we need explicit lifecycle control over panel contents (e.g., session
subscription teardown, memory management for heavy panels, keeping recently-
used panels warm), we'll adopt a portal pattern:

### The Concept
SwiftUI owns the **geometry** (the shell layout, panel chrome, animations).
We own the **view controllers** (creation, caching, destruction).

```
SwiftUI Shell
├── Sidebar (pure SwiftUI, lightweight)
├── Portal A (NSViewRepresentable — just an empty NSView rectangle)
└── Portal B (NSViewRepresentable — just an empty NSView rectangle)
```

Portals are dumb rectangles rendered by SwiftUI. Separately, we maintain a
pool of `NSViewController` instances (`SessionDetailVC`, `DocsTreeVC`, etc.)
whose lifecycle we manage entirely ourselves. Based on app state, we
`addChild` / `removeFromParent` a VC into whichever portal's backing NSView.

### Why NSViewRepresentable, Not NSViewControllerRepresentable
With `NSViewControllerRepresentable`, SwiftUI thinks it owns the VC — it
creates/destroys it based on view identity diffing. With a raw
`NSViewRepresentable` that vends a plain `NSView`, we control when to call
`addSubview` / `removeFromSuperview` and `addChild` / `removeFromParent`.
SwiftUI just sees a box.

### Recommended Structure
Use a VC representable as the portal container, with the real content VC
added as a child. This gives proper responder chain participation:

```
SwiftUI
└── PortalRepresentable (NSViewControllerRepresentable)
    └── PortalContainerVC (thin shell, we own it)
        └── child: SessionDetailVC (we manage lifecycle)
```

SwiftUI owns the `PortalRepresentable` identity, but `PortalContainerVC`
is just a shell. The real content VC is our child that we attach/detach
ourselves.

### Benefits
- **VC lifecycle = panel lifecycle.** `viewDidAppear`, `viewWillDisappear`,
  proper `removeFromParent()`. When a panel hides, we decide: keep VC alive
  (suspended) or tear it down.
- **Memory management.** If user navigates away from a heavy session, we can
  nil the VC and reclaim memory. Or keep a warm LRU cache.
- **Panel migration.** A VC can be moved from portal A to portal B (e.g.,
  doc detail moving from secondary to primary panel).
- **SwiftUI for animation.** Panel slide in/out, resize, springs — all stay
  in SwiftUI where animation is good. AppKit animation is not.
- **TCA still works.** Each VC hosts a `NSHostingController(rootView:
  SomeView(store: ...))`. Or for truly native AppKit panels, drive an
  AppKit VC directly via `store.observe {}`.

### Watch Out For
- **Keyboard focus / responder chain.** When embedding NSViewControllers
  inside SwiftUI, first responder can get confused. May need explicit
  `becomeFirstResponder` when panels activate.
- **Sheet/popover presentation.** VCs presenting sheets will present from
  their view, not the SwiftUI window. Better to drive all modals through
  SwiftUI (`.sheet`, `.alert`) at the shell level via TCA state.
- **Size negotiation.** SwiftUI proposes sizes top-down; AppKit VCs report
  intrinsic size bottom-up. For fixed-width panels (200pt, 280pt) this is
  fine. For auto-sizing, bridge `preferredContentSize` back via
  `PreferenceKey`.

### Phased Adoption
1. **Now:** Shell in SwiftUI, panel content as SwiftUI views. Fast iteration.
2. **Next:** Wrap each panel in a portal. VC hosts `NSHostingController`
   internally — same SwiftUI views, but with VC lifecycle hooks.
3. **Later:** For panels needing native AppKit performance (e.g., file tree
   with thousands of nodes), replace SwiftUI content inside the VC with
   native AppKit views.

This same architecture works on iPad with `UIViewControllerRepresentable`.
