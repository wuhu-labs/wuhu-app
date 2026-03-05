import ComposableArchitecture
import Foundation
import IdentifiedCollections
import WuhuAPI
import WuhuCoreClient

// MARK: - Sidebar Tab Selection (Column 1 tabs)

/// The tab selected in the first sidebar column. This determines what the
/// *second* column shows — it does NOT control the primary content (column 3).
enum SidebarTab: Hashable {
  case docs
  case messages
}

// MARK: - Sidebar Selection (Column 1 full selection state)

/// Represents the full selection state of the first sidebar. Either a tab
/// (docs / messages) or a session-list item (inbox or a specific session).
enum SidebarSelection: Hashable {
  case tab(SidebarTab)
  case inbox
}

// MARK: - App Feature

@Reducer
struct AppFeature {
  @ObservableState
  struct State {
    // --- Sidebar (column 1) ---
    /// Which sidebar item is highlighted. Determines what the second panel shows.
    var sidebarSelection: SidebarSelection? = .inbox

    /// Whether the second panel is visible.
    var isSecondPanelVisible = true

    /// Whether the sessions section is collapsed.
    var isSessionsSectionCollapsed = false

    /// Shows the "not implemented" alert for add-folder.
    var isShowingAddFolderAlert = false

    // --- Child features ---
    var sessions = SessionFeature.State()
    var docs = DocsFeature.State()
    var issues = IssuesFeature.State()
    var messages = MessagesFeature.State()

    // --- Workspace ---
    var workspaceName = "Wuhu"
    var isLoading = false
    var hasLoaded = false
    var isCreatingSession = false

    var workspaces: [Workspace] = []
    var activeWorkspace: Workspace = .default
    var isShowingWorkspaceSwitcher = false

    // --- Derived: which tab is active in the second panel ---
    var activeSecondPanelTab: SidebarTab? {
      switch sidebarSelection {
      case let .tab(tab): tab
      case .inbox: nil
      case nil: nil
      }
    }

    /// Whether the sidebar selection corresponds to the inbox/sessions area.
    var isInboxSelected: Bool {
      sidebarSelection == .inbox
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case onAppear
    case dataLoaded(
      sessions: IdentifiedArrayOf<MockSession>,
      docs: IdentifiedArrayOf<MockDoc>,
      issues: IdentifiedArrayOf<MockIssue>
    )
    case loadFailed
    case refreshTick
    case refreshDataLoaded(
      sessions: IdentifiedArrayOf<MockSession>,
      docs: IdentifiedArrayOf<MockDoc>,
      issues: IdentifiedArrayOf<MockIssue>
    )
    case createSessionTapped
    case sessionCreated(WuhuSession)
    case sessionCreateFailed(String)
    case docs(DocsFeature.Action)
    case issues(IssuesFeature.Action)
    case sessions(SessionFeature.Action)
    case messages(MessagesFeature.Action)

    // Sidebar
    case sidebarSelectionChanged(SidebarSelection?)
    case toggleSecondPanel
    case toggleSessionsSection
    case addFolderTapped

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
    BindingReducer()

    Scope(state: \.sessions, action: \.sessions) { SessionFeature() }
    Scope(state: \.issues, action: \.issues) { IssuesFeature() }
    Scope(state: \.docs, action: \.docs) { DocsFeature() }
    Scope(state: \.messages, action: \.messages) { MessagesFeature() }

    Reduce<State, Action> { state, action in
      switch action {
      case .binding:
        return .none

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
            uniqueElements: detailedSessions
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
            issues: IdentifiedArray(uniqueElements: issuesList)
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
              .map { MockSession.from($0) }
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
            issues: IdentifiedArray(uniqueElements: issuesList)
          ))
        } catch: { _, _ in }

      case let .refreshDataLoaded(sessions, docs, issues):
        // Merge sessions: preserve messages, detailed titles, and custom titles
        var mergedSessions: IdentifiedArrayOf<MockSession> = []
        for session in sessions {
          if var existing = state.sessions.sessions[id: session.id] {
            if existing.status != .running || session.status == .stopped {
              existing.status = session.status
            }
            existing.updatedAt = session.updatedAt
            existing.model = session.model
            existing.isArchived = session.isArchived
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

        // Merge docs
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

        // Merge issues
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

      // MARK: - Sidebar

      case let .sidebarSelectionChanged(selection):
        state.sidebarSelection = selection
        // When switching to a sidebar tab, show the second panel
        if case .tab = selection {
          state.isSecondPanelVisible = true
        }
        // When selecting inbox, show the second panel with session list
        if selection == .inbox {
          state.isSecondPanelVisible = true
        }
        return .none

      case .toggleSecondPanel:
        state.isSecondPanelVisible.toggle()
        // When hiding the second panel, clear sidebar tab selection
        // (but keep session selection since it drives primary content)
        if !state.isSecondPanelVisible {
          // Clear sidebar selection since nothing is visually selected
          state.sidebarSelection = nil
        }
        return .none

      case .toggleSessionsSection:
        state.isSessionsSectionCollapsed.toggle()
        return .none

      case .addFolderTapped:
        state.isShowingAddFolderAlert = true
        return .none

      // MARK: - Session creation

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
        state.sidebarSelection = .inbox
        state.isSecondPanelVisible = true
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

        if let url = URL(string: workspace.serverURL) {
          sharedBaseURL.update(url)
        }
        WorkspaceStorage.saveActiveWorkspaceID(workspace.id)

        state.activeWorkspace = workspace
        state.workspaceName = workspace.name
        state.isShowingWorkspaceSwitcher = false

        // Reset all loaded data
        state.sidebarSelection = .inbox
        state.sessions.sessions = []
        state.sessions.selectedSessionID = nil
        state.docs.docs = []
        state.docs.selectedDocID = nil
        state.issues.issues = []
        state.issues.selectedIssueID = nil

        state.hasLoaded = false
        state.isLoading = true
        state.hasLoaded = true

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
              uniqueElements: detailedSessions
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
              issues: IdentifiedArray(uniqueElements: issuesList)
            ))
          } catch: { _, send in
            await send(.loadFailed)
          }
        )

      case let .workspaceSwitcherToggled(shown):
        state.isShowingWorkspaceSwitcher = shown
        return .none

      case .docs, .issues, .sessions, .messages:
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
