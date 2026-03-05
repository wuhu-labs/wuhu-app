import ComposableArchitecture
import SwiftUI

// MARK: - App View

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  #if os(iOS)
    @State private var isShowingSettings = false
  #endif

  var body: some View {
    #if os(macOS)
      MacAppShell(store: store)
    #else
      iOSBody
    #endif
  }
}

// ╔══════════════════════════════════════════════════════════════════╗
// ║  macOS — Arc-style tri-panel shell                              ║
// ║                                                                 ║
// ║  ┌─────────┬────────────┬──────────────────────────────────┐    ║
// ║  │ traffic │            │                                  │    ║
// ║  │ lights  │            │                                  │    ║
// ║  │ ← → ↻   │            │                                  │    ║
// ║  │         │  Secondary │         Primary Content          │    ║
// ║  │ Sidebar │   Panel    │          (session, doc,          │    ║
// ║  │ (clear) │  (island)  │           chat, etc.)            │    ║
// ║  │         │            │           (island)               │    ║
// ║  │         │            │                                  │    ║
// ║  │  + ↻    │            │                                  │    ║
// ║  └─────────┴────────────┴──────────────────────────────────┘    ║
// ║                                                                 ║
// ║  The sidebar has no background — it's the window itself.        ║
// ║  Secondary + Primary are opaque islands with rounded corners    ║
// ║  floating on the translucent sidebar material.                  ║
// ╚══════════════════════════════════════════════════════════════════╝

#if os(macOS)

// MARK: - Layout Constants

enum PanelMetrics {
  /// Space between the window edge and panel islands.
  static let inset: CGFloat = 6
  /// Space between two adjacent panel islands.
  static let gap: CGFloat = 1
  /// Width of the first sidebar column.
  static let sidebarWidth: CGFloat = 200
  /// Width of the secondary (list) panel.
  static let secondaryWidth: CGFloat = 280

  // ── Titlebar / Nav Row ──────────────────────────────────────
  // The AppDelegate uses an empty NSToolbar with .unified style,
  // which creates a ~52pt titlebar. The traffic lights auto-center
  // in this taller titlebar. The nav row (sidebar toggle, back/forward)
  // sits in the same vertical strip via the safeAreaInset or top
  // padding. These values may need tuning after checking the actual
  // titlebar height printed by AppDelegate's debug output.

  /// Height of the titlebar area created by the .unified toolbar.
  /// Actual value printed by AppDelegate — update if it differs.
  static let titlebarHeight: CGFloat = 52
  /// Height of the navigation row. Should match or sit within the titlebar.
  static let navRowHeight: CGFloat = 52
}

// MARK: - Mac App Shell

struct MacAppShell: View {
  @Bindable var store: StoreOf<AppFeature>
  @Environment(\.windowCornerRadius) private var windowCornerRadius

  /// Concentric corner radius for panels that sit `inset` inside the window.
  private var panelRadius: CGFloat {
    max(windowCornerRadius - PanelMetrics.inset, 4)
  }

  var body: some View {
    ZStack {
      // Layer 0: Vibrancy material fills the entire window.
      SidebarMaterialBackground(
        tintColor: .orange,
        tintOpacity: 0.06
      )

      // Layer 1: The three-column layout.
      HStack(spacing: 0) {
        // Column 1 — Sidebar (transparent)
        sidebarColumn

        // Column 2 — Secondary panel (opaque island)
        if store.isSecondPanelVisible {
          secondaryPanelIsland
            .transition(.move(edge: .leading).combined(with: .opacity))
        }

        // Column 3 �� Primary content (opaque island)
        primaryContentIsland
      }
    }
    .frame(minWidth: 960, minHeight: 640)
    .ignoresSafeArea()
    .task { store.send(.onAppear) }
    .alert("Not Implemented", isPresented: $store.isShowingAddFolderAlert) {
      Button("OK") { }
    } message: {
      Text("Folders are not yet implemented.")
    }
  }

  // ──────────────────────────────────────────────────────────────
  // MARK: Column 1 — Sidebar
  // ──────────────────────────────────────────────────────────────

  private var sidebarColumn: some View {
    VStack(spacing: 0) {
      // Navigation row: sidebar toggle + back/forward + refresh
      // Sits at the same level as the traffic lights.
      navRow

      Divider()
        .padding(.horizontal, 16)
        .opacity(0.4)

      // Workspace switcher
      workspaceSwitcher
        .padding(.top, 8)
        .padding(.bottom, 4)

      // Tab buttons
      sidebarItem("Docs", icon: "doc.text", tag: .tab(.docs))
      sidebarItem("Messages", icon: "bubble.left.and.bubble.right", tag: .tab(.messages))

      smallDivider

      sidebarItem("Agents", icon: "cpu", tag: nil, disabled: true)
      sidebarItem("Settings", icon: "gearshape", tag: nil, disabled: true)

      smallDivider

      // Sessions section
      sessionsSection

      Spacer(minLength: 0)

      // Bottom actions
      bottomActions
    }
    .frame(width: PanelMetrics.sidebarWidth)
  }

  // MARK: Nav Row

  private var navRow: some View {
    HStack(spacing: 2) {
      // Leave space for the traffic lights — they sit to the left.
      // close + minimize + zoom ≈ 70pt wide
      Spacer()
        .frame(width: 76)

      sidebarToggleButton

      Spacer().frame(width: 4)

      navButton(icon: "chevron.left", help: "Back") { }
      navButton(icon: "chevron.right", help: "Forward") { }

      Spacer()

      navButton(icon: "arrow.clockwise", help: "Refresh") {
        store.send(.refreshTick)
      }
    }
    .frame(height: PanelMetrics.navRowHeight)
    .padding(.horizontal, 8)
  }

  private var sidebarToggleButton: some View {
    Button {
      _ = withAnimation(.easeInOut(duration: 0.2)) {
        store.send(.toggleSecondPanel)
      }
    } label: {
      Image(systemName: "sidebar.left")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(store.isSecondPanelVisible ? "Hide sidebar" : "Show sidebar")
  }

  private func navButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  // MARK: Workspace Switcher

  private var workspaceSwitcher: some View {
    Menu {
      ForEach(store.workspaces, id: \.id) { workspace in
        Button {
          store.send(.switchWorkspace(workspace))
        } label: {
          HStack {
            Text(workspace.name)
            if workspace.id == store.activeWorkspace.id {
              Image(systemName: "checkmark")
            }
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        VStack(alignment: .leading, spacing: 1) {
          Text(store.workspaceName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
          Text(store.activeWorkspace.serverURL)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
        }
        Spacer()
        Image(systemName: "chevron.up.chevron.down")
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
  }

  // MARK: Sidebar Items

  private func sidebarItem(
    _ title: String,
    icon: String,
    tag: SidebarSelection?,
    disabled: Bool = false
  ) -> some View {
    Button {
      if let tag {
        store.send(.sidebarSelectionChanged(tag))
      }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: icon)
          .font(.system(size: 13))
          .frame(width: 20)
        Text(title)
          .font(.system(size: 13))
        Spacer()
        if disabled {
          Text("Soon")
            .font(.caption2)
            .foregroundStyle(.quaternary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        store.sidebarSelection == tag && tag != nil
          ? Color.primary.opacity(0.08)
          : Color.clear
      )
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(disabled ? .tertiary : .secondary)
    .disabled(disabled)
    .padding(.horizontal, 8)
  }

  private var smallDivider: some View {
    Divider()
      .padding(.horizontal, 16)
      .padding(.vertical, 6)
      .opacity(0.4)
  }

  // MARK: Sessions Section

  private var sessionsSection: some View {
    VStack(spacing: 0) {
      // Section header (collapsible)
      Button {
        _ = withAnimation(.easeInOut(duration: 0.2)) {
          store.send(.toggleSessionsSection)
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .bold))
            .rotationEffect(.degrees(store.isSessionsSectionCollapsed ? 0 : 90))
          Text("SESSIONS")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if !store.isSessionsSectionCollapsed {
        // Inbox
        sidebarItem("Inbox", icon: "tray", tag: .inbox)

        // Add Folder (placeholder)
        Button {
          store.send(.addFolderTapped)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
              .font(.system(size: 12))
              .frame(width: 20)
            Text("Add Folder")
              .font(.system(size: 12))
            Spacer()
          }
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .foregroundStyle(.quaternary)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
      }
    }
  }

  // MARK: Bottom Actions

  private var bottomActions: some View {
    HStack(spacing: 6) {
      navButton(icon: "arrow.clockwise", help: "Refresh") {
        store.send(.refreshTick)
      }
      navButton(icon: "plus", help: "New Session") {
        store.send(.createSessionTapped)
      }
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  // ──────────────────────────────────────────────────────────────
  // MARK: Column 2 — Secondary Panel Island
  // ──────────────────────────────────────────────────────────────

  private var secondaryPanelIsland: some View {
    VStack(spacing: 0) {
      // Panel header
      HStack {
        Text(secondaryPanelTitle)
          .font(.system(size: 13, weight: .semibold))
        Spacer()
        Button {
          _ = withAnimation(.easeInOut(duration: 0.2)) {
            store.send(.toggleSecondPanel)
          }
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 20, height: 20)
            .background(Color.primary.opacity(0.05))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Hide panel")
      }
      .padding(.horizontal, 12)
      .padding(.top, 10)
      .padding(.bottom, 6)

      Divider().padding(.horizontal, 8)

      // Panel content
      secondaryPanelContent
        .frame(maxHeight: .infinity)
    }
    .frame(width: PanelMetrics.secondaryWidth)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: panelRadius))
    .padding(.top, PanelMetrics.inset)
    .padding(.bottom, PanelMetrics.inset)
    .padding(.leading, PanelMetrics.gap)
  }

  private var secondaryPanelTitle: String {
    switch store.sidebarSelection {
    case .tab(.docs): "Docs"
    case .tab(.messages): "Messages"
    case .inbox: "Sessions"
    case nil: ""
    }
  }

  @ViewBuilder
  private var secondaryPanelContent: some View {
    switch store.sidebarSelection {
    case .tab(.docs):
      DocsTreePanelView(store: store.scope(state: \.docs, action: \.docs))
    case .tab(.messages):
      MessagesListPanelView(store: store.scope(state: \.messages, action: \.messages))
    case .inbox:
      SessionListView(
        store: store.scope(state: \.sessions, action: \.sessions),
        onCreateSession: { store.send(.createSessionTapped) }
      )
    case nil:
      Spacer()
    }
  }

  // ──────────────────────────────────────────────────────────────
  // MARK: Column 3 — Primary Content Island
  // ──────────────────────────────────────────────────────────────

  private var primaryContentIsland: some View {
    primaryContentView
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color(nsColor: .windowBackgroundColor))
      .clipShape(
        // Left corners: concentric radius. Right corners: 0 (flush
        // with window edge — the OS rounds the window corners).
        UnevenRoundedRectangle(
          topLeadingRadius: panelRadius,
          bottomLeadingRadius: panelRadius,
          bottomTrailingRadius: 0,
          topTrailingRadius: 0
        )
      )
      .padding(.top, PanelMetrics.inset)
      .padding(.bottom, PanelMetrics.inset)
      .padding(.leading, PanelMetrics.gap)
  }

  @ViewBuilder
  private var primaryContentView: some View {
    if store.sessions.selectedSessionID != nil {
      SessionDetailView(store: store.scope(state: \.sessions, action: \.sessions))
    } else if store.docs.selectedDoc != nil {
      DocsDetailView(store: store.scope(state: \.docs, action: \.docs))
    } else if let channel = store.messages.selectedChannel {
      MessageChatPlaceholder(channel: channel)
    } else {
      emptyState
    }
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "sparkles")
        .font(.system(size: 40))
        .foregroundStyle(.tertiary)
      Text("Welcome to Wuhu")
        .font(.title2)
        .fontWeight(.semibold)
      Text("Select a session, document, or conversation to get started")
        .font(.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

// MARK: - Message Chat Placeholder

private struct MessageChatPlaceholder: View {
  let channel: MockChannel

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack(spacing: 10) {
        Text(channel.avatarEmoji).font(.title2)
        VStack(alignment: .leading, spacing: 1) {
          Text(channel.name).font(.headline)
          Text(channel.isGroup ? "\(channel.members.count) members" : "Direct message")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)

      Divider()

      Spacer()
      VStack(spacing: 8) {
        Text(channel.avatarEmoji).font(.system(size: 48))
        Text(channel.name).font(.title2).fontWeight(.semibold)
        Text("Messaging is coming soon.")
          .font(.body)
          .foregroundStyle(.secondary)
      }
      Spacer()
    }
  }
}

#endif

// ╔══════════════════════════════════════════════════════════════════╗
// ║  iOS — Standard NavigationSplitView                             ║
// ╚══════════════════════════════════════════════════════════════════╝

#if os(iOS)
  extension AppView {
    var iOSBody: some View {
      NavigationSplitView {
        iosSidebar
      } detail: {
        iosDetail
      }
      .tint(.orange)
      .task { store.send(.onAppear) }
      .sheet(isPresented: $isShowingSettings) {
        NavigationStack {
          SettingsView(
            workspaces: store.workspaces,
            activeWorkspace: store.activeWorkspace,
            onSwitchWorkspace: { ws in store.send(.switchWorkspace(ws)) }
          )
          .navigationTitle("Settings")
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isShowingSettings = false }
            }
          }
        }
      }
    }

    private var iosSidebar: some View {
      List {
        Section {
          Button { store.send(.sidebarSelectionChanged(.inbox)) } label: {
            Label("Sessions", systemImage: "terminal")
          }
          .listRowBackground(
            store.sidebarSelection == .inbox ? Color.orange.opacity(0.12) : nil
          )

          Button { store.send(.sidebarSelectionChanged(.tab(.docs))) } label: {
            Label("Docs", systemImage: "doc.text")
          }
          .listRowBackground(
            store.sidebarSelection == .tab(.docs) ? Color.orange.opacity(0.12) : nil
          )

          Button { store.send(.sidebarSelectionChanged(.tab(.messages))) } label: {
            Label("Messages", systemImage: "bubble.left.and.bubble.right")
          }
          .listRowBackground(
            store.sidebarSelection == .tab(.messages) ? Color.orange.opacity(0.12) : nil
          )
        }
      }
      .listStyle(.sidebar)
      .safeAreaInset(edge: .top) {
        iosWorkspaceSwitcherHeader
      }
      .navigationSplitViewColumnWidth(min: 180, ideal: 220)
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          HStack(spacing: 4) {
            Button { store.send(.refreshTick) } label: {
              Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button { store.send(.createSessionTapped) } label: {
              Image(systemName: "plus")
            }
            .help("New Session")

            Button { isShowingSettings = true } label: {
              Image(systemName: "gearshape")
            }
            .help("Settings")
          }
        }
      }
    }

    private var iosWorkspaceSwitcherHeader: some View {
      Menu {
        ForEach(store.workspaces, id: \.id) { workspace in
          Button {
            store.send(.switchWorkspace(workspace))
          } label: {
            HStack {
              Text(workspace.name)
              if workspace.id == store.activeWorkspace.id {
                Image(systemName: "checkmark")
              }
            }
          }
        }
      } label: {
        HStack(spacing: 6) {
          VStack(alignment: .leading, spacing: 1) {
            Text(store.workspaceName)
              .font(.headline)
              .foregroundStyle(.primary)
            Text(store.activeWorkspace.serverURL)
              .font(.caption2)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
          }
          Spacer()
          Image(systemName: "chevron.up.chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iosDetail: some View {
      switch store.sidebarSelection {
      case .inbox:
        NavigationStack {
          SessionListView(
            store: store.scope(state: \.sessions, action: \.sessions),
            onCreateSession: { store.send(.createSessionTapped) }
          )
          .navigationDestination(isPresented: Binding(
            get: { store.sessions.selectedSessionID != nil },
            set: { if !$0 { store.send(.sessions(.sessionSelected(nil))) } }
          )) {
            SessionDetailView(store: store.scope(state: \.sessions, action: \.sessions))
          }
        }
      case .tab(.docs):
        NavigationStack {
          DocsListView(store: store.scope(state: \.docs, action: \.docs))
            .navigationDestination(isPresented: Binding(
              get: { store.docs.selectedDocID != nil },
              set: { if !$0 { store.send(.docs(.docSelected(nil))) } }
            )) {
              DocsDetailView(store: store.scope(state: \.docs, action: \.docs))
            }
        }
      case .tab(.messages):
        ContentUnavailableView(
          "Messages",
          systemImage: "bubble.left.and.bubble.right",
          description: Text("Messaging is coming soon.")
        )
      case nil:
        ContentUnavailableView(
          "Select an item",
          systemImage: "sidebar.left",
          description: Text("Choose something from the sidebar")
        )
      }
    }
  }
#endif

// MARK: - Preview

#Preview {
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
