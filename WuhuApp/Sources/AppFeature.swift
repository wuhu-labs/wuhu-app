import ComposableArchitecture
import IdentifiedCollections
import SwiftUI
import WuhuAPI
import WuhuCoreClient

// MARK: - Sidebar Selection

enum SidebarSelection: Hashable {
  case sessions
  case issues
  case docs
}

// MARK: - App Feature

@Reducer
struct AppFeature {
  @ObservableState
  struct State {
    var selection: SidebarSelection? = .sessions
    var sessions = SessionFeature.State()
    var issues = IssuesFeature.State()
    var docs = DocsFeature.State()
    var workspaceName = "Wuhu"
    var isLoading = false
    var hasLoaded = false
    var isCreatingSession = false

    // Workspace state
    var workspaces: [Workspace] = []
    var activeWorkspace: Workspace = .default
    var isShowingWorkspaceSwitcher = false
  }

  enum Action {
    case onAppear
    case dataLoaded(
      sessions: IdentifiedArrayOf<MockSession>,
      docs: IdentifiedArrayOf<MockDoc>,
      issues: IdentifiedArrayOf<MockIssue>,
    )
    case loadFailed
    case refreshTick
    case refreshDataLoaded(
      sessions: IdentifiedArrayOf<MockSession>,
      docs: IdentifiedArrayOf<MockDoc>,
      issues: IdentifiedArrayOf<MockIssue>,
    )
    case createSessionTapped
    case sessionCreated(WuhuSession)
    case sessionCreateFailed(String)
    case docs(DocsFeature.Action)
    case issues(IssuesFeature.Action)
    case selectionChanged(SidebarSelection?)
    case sessions(SessionFeature.Action)

    // Workspace
    case workspacesLoaded([Workspace], active: Workspace)
    case switchWorkspace(Workspace)
    case workspaceSwitcherToggled(Bool)
  }

  private enum CancelID {
    case refreshTimer
  }

  @Dependency(\.apiClient) var apiClient
  @Dependency(\.continuousClock) var clock

  var body: some ReducerOf<Self> {
    Scope(state: \.sessions, action: \.sessions) { SessionFeature() }
    Scope(state: \.issues, action: \.issues) { IssuesFeature() }
    Scope(state: \.docs, action: \.docs) { DocsFeature() }

    Reduce<State, Action> { state, action in
      switch action {
      case .onAppear:
        guard !state.hasLoaded else { return .none }
        state.isLoading = true
        state.hasLoaded = true

        // Load workspaces from storage
        let workspaces = WorkspaceStorage.loadWorkspaces()
        let activeID = WorkspaceStorage.loadActiveWorkspaceID()
        let active = workspaces.first(where: { $0.id == activeID }) ?? workspaces.first ?? .default
        state.workspaces = workspaces
        state.activeWorkspace = active
        state.workspaceName = active.name

        // Update the shared base URL
        if let url = URL(string: active.serverURL) {
          sharedBaseURL.update(url)
        }
        WorkspaceStorage.saveActiveWorkspaceID(active.id)

        let showArchived = state.sessions.showArchived
        return .run { send in
          async let sessionsResult = apiClient.listSessions(showArchived)
          async let docsResult = apiClient.listWorkspaceDocs()

          let allSessions = try await sessionsResult
          let allDocs = try await docsResult

          let sortedSessions = allSessions.sorted(by: { $0.updatedAt > $1.updatedAt })
          // Fetch session details concurrently for accurate running status
          let detailedSessions = await withTaskGroup(of: MockSession.self) { group in
            for session in sortedSessions {
              group.addTask {
                if let response = try? await apiClient.getSession(session.id) {
                  return MockSession.from(response)
                }
                return MockSession.from(session)
              }
            }
            var results: [MockSession] = []
            for await session in group {
              results.append(session)
            }
            return results.sorted(by: { $0.updatedAt > $1.updatedAt })
          }
          let mockSessions: IdentifiedArrayOf<MockSession> = IdentifiedArray(
            uniqueElements: detailedSessions,
          )

          // Parse workspace docs into docs and issues.
          // Use file path as the primary signal: files under "issues/" are
          // issues, everything else is a doc.
          var docsList: [MockDoc] = []
          var issuesList: [MockIssue] = []
          for doc in allDocs {
            if doc.path.hasPrefix("issues/"), let issue = MockIssue.from(doc) {
              issuesList.append(issue)
            } else {
              docsList.append(MockDoc.from(doc))
            }
          }

          await send(.dataLoaded(
            sessions: mockSessions,
            docs: IdentifiedArray(uniqueElements: docsList),
            issues: IdentifiedArray(uniqueElements: issuesList),
          ))
        } catch: { _, send in
          await send(.loadFailed)
        }

      case let .dataLoaded(sessions, docs, issues):
        state.isLoading = false
        state.sessions.sessions = sessions
        state.docs.docs = docs
        state.issues.issues = issues
        return refreshTimerEffect()

      case .loadFailed:
        state.isLoading = false
        return .none

      case .refreshTick:
        let showArchived = state.sessions.showArchived
        return .run { send in
          async let sessionsResult = apiClient.listSessions(showArchived)
          async let docsResult = apiClient.listWorkspaceDocs()

          let allSessions = try await sessionsResult
          let allDocs = try await docsResult

          let mockSessions: IdentifiedArrayOf<MockSession> = IdentifiedArray(
            uniqueElements: allSessions
              .sorted(by: { $0.updatedAt > $1.updatedAt })
              .map { MockSession.from($0) },
          )

          var docsList: [MockDoc] = []
          var issuesList: [MockIssue] = []
          for doc in allDocs {
            if doc.path.hasPrefix("issues/"), let issue = MockIssue.from(doc) {
              issuesList.append(issue)
            } else {
              docsList.append(MockDoc.from(doc))
            }
          }

          await send(.refreshDataLoaded(
            sessions: mockSessions,
            docs: IdentifiedArray(uniqueElements: docsList),
            issues: IdentifiedArray(uniqueElements: issuesList),
          ))
        } catch: { _, _ in }

      case let .refreshDataLoaded(sessions, docs, issues):
        // Merge sessions: preserve messages, detailed titles, and custom titles
        var mergedSessions: IdentifiedArrayOf<MockSession> = []
        for session in sessions {
          if var existing = state.sessions.sessions[id: session.id] {
            // Preserve running status: the list-sessions heuristic cannot detect
            // running state (only getSession can), so don't downgrade it.
            if existing.status != .running || session.status == .stopped {
              existing.status = session.status
            }
            existing.updatedAt = session.updatedAt
            existing.model = session.model
            existing.isArchived = session.isArchived
            // If the server returns a custom title, adopt it; otherwise preserve
            // any locally-set custom title from a prior rename.
            if let serverCustomTitle = session.customTitle {
              existing.customTitle = serverCustomTitle
              existing.title = serverCustomTitle
            }
            mergedSessions.append(existing)
          } else {
            mergedSessions.append(session)
          }
        }
        state.sessions.sessions = mergedSessions

        // Merge docs: preserve loaded markdownContent
        var mergedDocs: IdentifiedArrayOf<MockDoc> = []
        for doc in docs {
          if let existing = state.docs.docs[id: doc.id], !existing.markdownContent.isEmpty {
            var updated = doc
            updated.markdownContent = existing.markdownContent
            mergedDocs.append(updated)
          } else {
            mergedDocs.append(doc)
          }
        }
        state.docs.docs = mergedDocs

        // Merge issues: preserve loaded markdownContent
        var mergedIssues: IdentifiedArrayOf<MockIssue> = []
        for issue in issues {
          if let existing = state.issues.issues[id: issue.id], !existing.markdownContent.isEmpty {
            var updated = issue
            updated.markdownContent = existing.markdownContent
            mergedIssues.append(updated)
          } else {
            mergedIssues.append(issue)
          }
        }
        state.issues.issues = mergedIssues

        return .none

      case let .selectionChanged(selection):
        state.selection = selection
        return .none

      case .createSessionTapped:
        guard !state.isCreatingSession else { return .none }
        state.isCreatingSession = true
        let request = WuhuCreateSessionRequest(provider: .anthropic)
        return .run { send in
          let session = try await apiClient.createSession(request)
          await send(.sessionCreated(session))
        } catch: { _, send in
          await send(.sessionCreateFailed("Failed to create session"))
        }

      case let .sessionCreated(session):
        state.isCreatingSession = false
        let mockSession = MockSession.from(session)
        state.sessions.sessions.insert(mockSession, at: 0)
        state.selection = .sessions
        return .send(.sessions(.sessionSelected(mockSession.id)))

      case .sessionCreateFailed:
        state.isCreatingSession = false
        return .none

      // MARK: - Workspace

      case let .workspacesLoaded(workspaces, active):
        state.workspaces = workspaces
        state.activeWorkspace = active
        state.workspaceName = active.name
        return .none

      case let .switchWorkspace(workspace):
        guard workspace.id != state.activeWorkspace.id else { return .none }

        // Update shared base URL
        if let url = URL(string: workspace.serverURL) {
          sharedBaseURL.update(url)
        }

        // Persist selection
        WorkspaceStorage.saveActiveWorkspaceID(workspace.id)

        // Update state
        state.activeWorkspace = workspace
        state.workspaceName = workspace.name
        state.isShowingWorkspaceSwitcher = false

        // Reset all loaded data
        state.selection = .sessions
        state.sessions.sessions = []
        state.sessions.selectedSessionID = nil
        state.docs.docs = []
        state.docs.selectedDocID = nil
        state.issues.issues = []
        state.issues.selectedIssueID = nil

        // Mark as needing reload and trigger it
        state.hasLoaded = false
        state.isLoading = true
        state.hasLoaded = true

        // Cancel existing subscriptions and timers, then reload
        let showArchived = state.sessions.showArchived
        return .merge(
          .cancel(id: CancelID.refreshTimer),
          .run { send in
            async let sessionsResult = apiClient.listSessions(showArchived)
            async let docsResult = apiClient.listWorkspaceDocs()

            let allSessions = try await sessionsResult
            let allDocs = try await docsResult

            let sortedSessions = allSessions.sorted(by: { $0.updatedAt > $1.updatedAt })
            let detailedSessions = await withTaskGroup(of: MockSession.self) { group in
              for session in sortedSessions {
                group.addTask {
                  if let response = try? await apiClient.getSession(session.id) {
                    return MockSession.from(response)
                  }
                  return MockSession.from(session)
                }
              }
              var results: [MockSession] = []
              for await session in group {
                results.append(session)
              }
              return results.sorted(by: { $0.updatedAt > $1.updatedAt })
            }
            let mockSessions: IdentifiedArrayOf<MockSession> = IdentifiedArray(
              uniqueElements: detailedSessions,
            )

            var docsList: [MockDoc] = []
            var issuesList: [MockIssue] = []
            for doc in allDocs {
              if doc.path.hasPrefix("issues/"), let issue = MockIssue.from(doc) {
                issuesList.append(issue)
              } else {
                docsList.append(MockDoc.from(doc))
              }
            }

            await send(.dataLoaded(
              sessions: mockSessions,
              docs: IdentifiedArray(uniqueElements: docsList),
              issues: IdentifiedArray(uniqueElements: issuesList),
            ))
          } catch: { _, send in
            await send(.loadFailed)
          },
        )

      case let .workspaceSwitcherToggled(shown):
        state.isShowingWorkspaceSwitcher = shown
        return .none

      case .docs, .issues, .sessions:
        return .none
      }
    }

  }

  private func refreshTimerEffect() -> Effect<Action> {
    .run { send in
      for await _ in clock.timer(interval: .seconds(20)) {
        await send(.refreshTick)
      }
    }
    .cancellable(id: CancelID.refreshTimer, cancelInFlight: true)
  }
}

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

// MARK: - Entry Point

@main
struct WuhuApp: App {
  #if os(macOS)
  @StateObject private var updater = SoftwareUpdater()
  #endif

  var body: some Scene {
    WindowGroup {
      AppView(
        store: Store(initialState: AppFeature.State()) {
          AppFeature()
        },
      )
    }
    #if os(macOS)
    .windowStyle(.automatic)
    .defaultSize(width: 1200, height: 750)
    .commands {
      CheckForUpdatesCommand(updater: updater)
    }
    #endif

    #if os(macOS)
      Settings {
        SettingsView(
          workspaces: WorkspaceStorage.loadWorkspaces(),
          activeWorkspace: {
            let ws = WorkspaceStorage.loadWorkspaces()
            let id = WorkspaceStorage.loadActiveWorkspaceID()
            return ws.first(where: { $0.id == id }) ?? ws.first ?? .default
          }(),
          onSwitchWorkspace: nil,
        )
      }
    #endif
  }
}

// MARK: - Settings

struct SettingsView: View {
  @AppStorage("wuhuUsername") private var username = ""
  @State private var workspaces: [Workspace]
  @State private var activeWorkspace: Workspace
  var onSwitchWorkspace: ((Workspace) -> Void)?

  @State private var isAddingWorkspace = false
  @State private var newWorkspaceName = ""
  @State private var newWorkspaceURL = "http://localhost:8080"

  @State private var editingWorkspace: Workspace?
  @State private var editName = ""
  @State private var editURL = ""

  init(
    workspaces: [Workspace],
    activeWorkspace: Workspace,
    onSwitchWorkspace: ((Workspace) -> Void)?,
  ) {
    _workspaces = State(initialValue: workspaces)
    _activeWorkspace = State(initialValue: activeWorkspace)
    self.onSwitchWorkspace = onSwitchWorkspace
  }

  var body: some View {
    Form {
      Section("Workspaces") {
        ForEach(workspaces, id: \.id) { workspace in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(workspace.name)
                  .fontWeight(workspace.id == activeWorkspace.id ? .semibold : .regular)
                if workspace.id == activeWorkspace.id {
                  Text("Active")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
              }
              Text(workspace.serverURL)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if workspace.id != activeWorkspace.id {
              Button("Switch") {
                switchTo(workspace)
              }
              .buttonStyle(.borderless)
            }
            Button {
              editingWorkspace = workspace
              editName = workspace.name
              editURL = workspace.serverURL
            } label: {
              Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            if workspaces.count > 1 {
              Button(role: .destructive) {
                removeWorkspace(workspace)
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
            }
          }
          .padding(.vertical, 2)
        }

        Button {
          isAddingWorkspace = true
          newWorkspaceName = ""
          newWorkspaceURL = "http://localhost:8080"
        } label: {
          Label("Add Workspace", systemImage: "plus")
        }
      }

      Section("Identity") {
        TextField("Username", text: $username)
          .textFieldStyle(.roundedBorder)
        Text("Displayed as the author of your messages.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
      .frame(width: 480)
    #endif
      .alert("Add Workspace", isPresented: $isAddingWorkspace) {
        TextField("Name", text: $newWorkspaceName)
        TextField("Server URL", text: $newWorkspaceURL)
        Button("Add") { addWorkspace() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Enter a name and server URL for the new workspace.")
      }
      .alert("Edit Workspace", isPresented: Binding(
        get: { editingWorkspace != nil },
        set: { if !$0 { editingWorkspace = nil } },
      )) {
        TextField("Name", text: $editName)
        TextField("Server URL", text: $editURL)
        Button("Save") { saveEditedWorkspace() }
        Button("Cancel", role: .cancel) { editingWorkspace = nil }
      } message: {
        Text("Update the workspace name and server URL.")
      }
  }

  private func addWorkspace() {
    let name = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = newWorkspaceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !url.isEmpty else { return }
    let workspace = Workspace(name: name, serverURL: url)
    workspaces.append(workspace)
    WorkspaceStorage.saveWorkspaces(workspaces)
  }

  private func removeWorkspace(_ workspace: Workspace) {
    workspaces.removeAll { $0.id == workspace.id }
    WorkspaceStorage.saveWorkspaces(workspaces)
    // If we removed the active one, switch to the first available
    if workspace.id == activeWorkspace.id, let first = workspaces.first {
      switchTo(first)
    }
  }

  private func switchTo(_ workspace: Workspace) {
    activeWorkspace = workspace
    WorkspaceStorage.saveActiveWorkspaceID(workspace.id)
    onSwitchWorkspace?(workspace)
  }

  private func saveEditedWorkspace() {
    guard let editing = editingWorkspace else { return }
    let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = editURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !url.isEmpty else { return }

    if let index = workspaces.firstIndex(where: { $0.id == editing.id }) {
      workspaces[index].name = name
      workspaces[index].serverURL = url
      WorkspaceStorage.saveWorkspaces(workspaces)

      // If we edited the active workspace, update it and notify
      if editing.id == activeWorkspace.id {
        activeWorkspace = workspaces[index]
        // Update shared URL and notify reducer
        if let parsedURL = URL(string: url) {
          sharedBaseURL.update(parsedURL)
        }
        onSwitchWorkspace?(workspaces[index])
      }
    }
    editingWorkspace = nil
  }
}

#Preview {
  AppView(
    store: Store(initialState: AppFeature.State()) {
      AppFeature()
    },
  )
}
