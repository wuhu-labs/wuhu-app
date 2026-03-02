import ComposableArchitecture

@Reducer
struct DocsFeature {
  @ObservableState
  struct State {
    var docs: IdentifiedArrayOf<MockDoc> = []
    var selectedDocID: String?
    var isLoadingContent = false

    var selectedDoc: MockDoc? {
      guard let id = selectedDocID else { return nil }
      return docs[id: id]
    }
  }

  enum Action {
    case docSelected(String?)
    case docContentLoaded(MockDoc)
    case docContentLoadFailed
  }

  @Dependency(\.apiClient) var apiClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .docSelected(id):
        state.selectedDocID = id
        guard let id else {
          state.isLoadingContent = false
          return .none
        }
        guard let doc = state.docs[id: id] else { return .none }
        // If content is already loaded, don't re-fetch
        if !doc.markdownContent.isEmpty { return .none }
        state.isLoadingContent = true
        return .run { send in
          let fullDoc = try await apiClient.readWorkspaceDoc(id)
          await send(.docContentLoaded(MockDoc.from(fullDoc)))
        } catch: { _, send in
          await send(.docContentLoadFailed)
        }

      case let .docContentLoaded(doc):
        state.isLoadingContent = false
        state.docs[id: doc.id] = doc
        return .none

      case .docContentLoadFailed:
        state.isLoadingContent = false
        return .none
      }
    }
  }
}
