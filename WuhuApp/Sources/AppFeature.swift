import ComposableArchitecture
import Foundation
import IdentifiedCollections
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
