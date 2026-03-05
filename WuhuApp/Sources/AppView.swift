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
      macOSBody
    #else
      iOSBody
    #endif
  }
}

// MARK: - macOS: Arc-style Tri-Panel Layout

#if os(macOS)
  extension AppView {
    var macOSBody: some View {
      HStack(spacing: 0) {
        // Column 1: Sidebar (transparent, part of the window)
        sidebarColumn
          .frame(width: 200)

        // Columns 2 & 3: Floating content area
        floatingContentArea
      }
      .frame(minWidth: 900, minHeight: 600)
      .background(WindowBackgroundView())
      .task { store.send(.onAppear) }
      .alert("Not Implemented", isPresented: $store.isShowingAddFolderAlert) {
        Button("OK") { }
      } message: {
        Text("Folders are not yet implemented.")
      }
    }

    // MARK: - Sidebar Column (Column 1)

    private var sidebarColumn: some View {
      VStack(spacing: 0) {
        // Workspace Switcher
        workspaceSwitcherHeader
          .padding(.top, 36) // space for traffic lights

        Spacer().frame(height: 12)

        // Tab buttons
        sidebarTabButton("Docs", icon: "doc.text", selection: .tab(.docs))
        sidebarTabButton("Messages", icon: "bubble.left.and.bubble.right", selection: .tab(.messages))

        Divider()
          .padding(.horizontal, 16)
          .padding(.vertical, 8)

        sidebarTabButton("Agents", icon: "cpu", selection: nil, disabled: true)
        sidebarTabButton("Settings", icon: "gearshape", selection: nil, disabled: true)

        Divider()
          .padding(.horizontal, 16)
          .padding(.vertical, 8)

        // Sessions section
        sessionsSection

        Spacer()

        // Bottom toolbar
        sidebarBottomBar
      }
      .padding(.horizontal, 4)
    }

    private func sidebarTabButton(
      _ title: String,
      icon: String,
      selection: SidebarSelection?,
      disabled: Bool = false
    ) -> some View {
      Button {
        if let selection {
          store.send(.sidebarSelectionChanged(selection))
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
              .foregroundStyle(.tertiary)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
          store.sidebarSelection == selection && selection != nil
            ? Color.white.opacity(0.1)
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

    // MARK: Sessions Section

    private var sessionsSection: some View {
      VStack(spacing: 0) {
        // Section header
        Button {
          _ = withAnimation(.easeInOut(duration: 0.2)) {
            store.send(.toggleSessionsSection)
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "chevron.right")
              .font(.system(size: 9, weight: .semibold))
              .rotationEffect(.degrees(store.isSessionsSectionCollapsed ? 0 : 90))
            Text("Sessions")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 4)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if !store.isSessionsSectionCollapsed {
          // Inbox
          sidebarSessionItem(
            "Inbox",
            icon: "tray",
            isSelected: store.sidebarSelection == .inbox,
            count: store.sessions.sessions.count(where: { $0.status == .running })
          ) {
            store.send(.sidebarSelectionChanged(.inbox))
          }

          // Add Folder button
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
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .padding(.horizontal, 8)
        }
      }
    }

    private func sidebarSessionItem(
      _ title: String,
      icon: String,
      isSelected: Bool,
      count: Int = 0,
      action: @escaping () -> Void
    ) -> some View {
      Button(action: action) {
        HStack(spacing: 8) {
          Image(systemName: icon)
            .font(.system(size: 13))
            .frame(width: 20)
          Text(title)
            .font(.system(size: 13))
          Spacer()
          if count > 0 {
            Text("\(count)")
              .font(.caption2)
              .fontWeight(.semibold)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(.orange.opacity(0.25))
              .foregroundStyle(.orange)
              .clipShape(Capsule())
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.white.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 8)
    }

    // MARK: Sidebar Bottom Bar

    private var sidebarBottomBar: some View {
      HStack(spacing: 4) {
        Button {
          store.send(.refreshTick)
        } label: {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Refresh")

        Button {
          store.send(.createSessionTapped)
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("New Session")

        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }

    // MARK: - Floating Content Area (Columns 2 & 3)

    private var floatingContentArea: some View {
      HStack(spacing: 1) {
        // Column 2: Secondary panel (session list / doc tree / chat list)
        if store.isSecondPanelVisible {
          secondaryPanel
            .frame(width: 280)
            .transition(.move(edge: .leading).combined(with: .opacity))
        }

        // Column 3: Primary content (session detail / doc viewer / chat)
        primaryContentPanel
          .frame(maxWidth: .infinity)
      }
      .padding(6)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(.ultraThinMaterial)
          .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
      )
      .padding(.top, 6)
      .padding(.trailing, 6)
      .padding(.bottom, 6)
    }

    // MARK: - Secondary Panel (Column 2)

    @ViewBuilder
    private var secondaryPanel: some View {
      VStack(spacing: 0) {
        // Header with hide button
        HStack {
          Text(secondaryPanelTitle)
            .font(.headline)
            .foregroundStyle(.primary)
          Spacer()
          Button {
            _ = withAnimation(.easeInOut(duration: 0.2)) {
              store.send(.toggleSecondPanel)
            }
          } label: {
            Image(systemName: "sidebar.left")
              .font(.system(size: 13))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .help("Hide panel")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)

        Divider()

        // Content based on sidebar selection
        secondaryPanelContent
      }
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(nsColor: .controlBackgroundColor.withAlphaComponent(0.5)))
      )
      .clipShape(RoundedRectangle(cornerRadius: 8))
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
        docsTreePanel
      case .tab(.messages):
        messagesListPanel
      case .inbox:
        SessionListView(
          store: store.scope(state: \.sessions, action: \.sessions),
          onCreateSession: { store.send(.createSessionTapped) }
        )
      case nil:
        Color.clear
      }
    }

    // MARK: Docs Tree Panel

    private var docsTreePanel: some View {
      let docsStore = store.scope(state: \.docs, action: \.docs)
      return DocsTreePanelView(store: docsStore)
    }

    // MARK: Messages List Panel

    private var messagesListPanel: some View {
      MessagesListPanelView(store: store.scope(state: \.messages, action: \.messages))
    }

    // MARK: - Primary Content Panel (Column 3)

    @ViewBuilder
    private var primaryContentPanel: some View {
      Group {
        if store.sessions.selectedSessionID != nil {
          // A session is selected — show its detail regardless of sidebar state
          SessionDetailView(store: store.scope(state: \.sessions, action: \.sessions))
        } else if store.docs.selectedDoc != nil {
          // A doc is selected from the docs tree
          DocsDetailView(store: store.scope(state: \.docs, action: \.docs))
        } else if let channel = store.messages.selectedChannel {
          // A message channel is selected — show placeholder chat
          messageChatPlaceholder(channel)
        } else {
          ContentUnavailableView(
            "Welcome to Wuhu",
            systemImage: "sparkles",
            description: Text("Select a session, document, or conversation to get started")
          )
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func messageChatPlaceholder(_ channel: MockChannel) -> some View {
      VStack(spacing: 0) {
        // Chat header
        HStack(spacing: 10) {
          Text(channel.avatarEmoji)
            .font(.title2)
          VStack(alignment: .leading, spacing: 1) {
            Text(channel.name)
              .font(.headline)
            Text(channel.isGroup
              ? "\(channel.members.count) members"
              : "Direct message")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)

        Divider()

        // Placeholder content
        Spacer()
        VStack(spacing: 8) {
          Text(channel.avatarEmoji)
            .font(.system(size: 48))
          Text(channel.name)
            .font(.title2)
            .fontWeight(.semibold)
          Text("This is a preview. Messaging is coming soon.")
            .font(.body)
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
    }

    // MARK: - Workspace Switcher Header

    private var workspaceSwitcherHeader: some View {
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
  }

  // MARK: - Window Background Helper

  /// Renders the window's background as transparent so the sidebar blends
  /// with the window chrome like Arc's sidebar.
  struct WindowBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
      let view = NSVisualEffectView()
      view.material = .sidebar
      view.blendingMode = .behindWindow
      view.state = .active
      return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
  }
#endif

// MARK: - iOS: Preserved NavigationSplitView

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

#Preview {
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    }
  )
}
