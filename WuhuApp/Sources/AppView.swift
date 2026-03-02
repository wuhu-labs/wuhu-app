import ComposableArchitecture
import SwiftUI

// MARK: - App View (two-column NavigationSplitView)

struct AppView: View {
  @Bindable var store: StoreOf<AppFeature>
  #if os(iOS)
    @State private var isShowingSettings = false
  #endif

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      detailColumn
    }
    .tint(.orange)
    #if os(macOS)
      .frame(minWidth: 900, minHeight: 600)
    #endif
      .task { store.send(.onAppear) }
    #if os(iOS)
      .sheet(isPresented: $isShowingSettings) {
        NavigationStack {
          SettingsView(
            workspaces: store.workspaces,
            activeWorkspace: store.activeWorkspace,
            onSwitchWorkspace: { ws in store.send(.switchWorkspace(ws)) },
          )
          .navigationTitle("Settings")
          .toolbar {
            ToolbarItem(placement: .confirmationAction) {
              Button("Done") { isShowingSettings = false }
            }
          }
        }
      }
    #endif
  }

  // MARK: - Sidebar (column 1)

  private var sidebar: some View {
    List(selection: $store.selection.sending(\.selectionChanged)) {
      sidebarRow(
        "Sessions", icon: "terminal", tag: .sessions,
        count: store.sessions.sessions.count(where: { $0.status == .running }),
      )
      sidebarRow(
        "Issues", icon: "checklist", tag: .issues,
        count: store.issues.issues.count(where: { $0.status == .open }),
      )
      sidebarRow("Docs", icon: "doc.text", tag: .docs)
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .top) {
      workspaceSwitcherHeader
    }
    .navigationSplitViewColumnWidth(min: 180, ideal: 220)
    .toolbar {
      ToolbarItemGroup(placement: .primaryAction) {
        HStack(spacing: 4) {
          Button {
            store.send(.refreshTick)
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .help("Refresh")

          #if os(macOS)
          Button {
            store.send(.createSessionTapped)
          } label: {
            Image(systemName: "plus")
          }
          .help("New Session")
          #endif

          #if os(iOS)
            Button {
              isShowingSettings = true
            } label: {
              Image(systemName: "gearshape")
            }
            .help("Settings")
          #endif
        }
      }
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

  private func sidebarRow(_ title: String, icon: String, tag: SidebarSelection, count: Int = 0) -> some View {
    Label {
      HStack {
        Text(title)
        Spacer()
        if count > 0 {
          Text("\(count)")
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.2))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
        }
      }
    } icon: {
      Image(systemName: icon)
    }
    .tag(tag)
  }

  // MARK: - Detail

  @ViewBuilder
  private var detailColumn: some View {
    switch store.selection {
    case .sessions:
      dualPane {
        SessionListView(
          store: store.scope(state: \.sessions, action: \.sessions),
          onCreateSession: { store.send(.createSessionTapped) }
        )
      } detail: {
        SessionDetailView(store: store.scope(state: \.sessions, action: \.sessions))
      }
    case .issues:
      IssuesDetailView(store: store.scope(state: \.issues, action: \.issues))
    case .docs:
      dualPane {
        DocsListView(store: store.scope(state: \.docs, action: \.docs))
      } detail: {
        DocsDetailView(store: store.scope(state: \.docs, action: \.docs))
      }
    case nil:
      ContentUnavailableView("Select an item", systemImage: "sidebar.left", description: Text("Choose something from the sidebar"))
    }
  }

  /// On macOS, renders a fixed-width list alongside the detail view.
  /// On iOS, renders the list with a navigation push to the detail.
  private func dualPane(
    @ViewBuilder list: () -> some View,
    @ViewBuilder detail: () -> some View,
  ) -> some View {
    #if os(macOS)
      HStack(spacing: 0) {
        list()
          .frame(width: 280)
        Divider()
        detail()
          .frame(maxWidth: .infinity)
      }
    #else
      NavigationStack {
        list()
          .navigationDestination(isPresented: Binding(
            get: { hasDetailSelection },
            set: { if !$0 { clearDetailSelection() } },
          )) {
            detail()
          }
      }
    #endif
  }

  #if os(iOS)
    /// Whether the current top-level section has a selected detail item.
    private var hasDetailSelection: Bool {
      switch store.selection {
      case .sessions: store.sessions.selectedSessionID != nil
      case .docs: store.docs.selectedDocID != nil
      default: false
      }
    }

    /// Clear the detail selection for the current section (on back navigation).
    private func clearDetailSelection() {
      switch store.selection {
      case .sessions: store.send(.sessions(.sessionSelected(nil)))
      case .docs: store.send(.docs(.docSelected(nil)))
      default: break
      }
    }
  #endif
}

#Preview {
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    },
  )
}
