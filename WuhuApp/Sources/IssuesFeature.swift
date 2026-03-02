import ComposableArchitecture

@Reducer
struct IssuesFeature {
  @ObservableState
  struct State {
    var issues: IdentifiedArrayOf<MockIssue> = []
    var selectedIssueID: String?
    var popoverIssueID: String?

    var selectedIssue: MockIssue? {
      guard let id = selectedIssueID else { return nil }
      return issues[id: id]
    }
  }

  enum Action {
    case issueSelected(String?)
    case popoverIssueChanged(String?)
    case issueContentLoaded(MockIssue)
    case issueContentLoadFailed
  }

  @Dependency(\.apiClient) var apiClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .issueSelected(id):
        state.selectedIssueID = id
        return .none

      case let .popoverIssueChanged(id):
        state.popoverIssueID = id
        guard let id else { return .none }
        guard let issue = state.issues[id: id] else { return .none }
        // If content is already loaded, don't re-fetch
        if !issue.markdownContent.isEmpty { return .none }
        return .run { send in
          let doc = try await apiClient.readWorkspaceDoc(id)
          await send(.issueContentLoaded(MockIssue.from(doc, existing: issue)))
        } catch: { _, send in
          await send(.issueContentLoadFailed)
        }

      case let .issueContentLoaded(issue):
        state.issues[id: issue.id] = issue
        return .none

      case .issueContentLoadFailed:
        return .none
      }
    }
  }
}
