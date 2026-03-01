import ComposableArchitecture
import PiAI
import SwiftUI
import WuhuAPI

@Reducer
struct CreateSessionFeature {
  @ObservableState
  struct State: Equatable {
    var provider: WuhuProvider = .anthropic
    var modelSelection: String = ""
    var customModel: String = ""
    var reasoningEffort: ReasoningEffort?
    var isCreating = false
    var error: String?

    var resolvedModelID: String? {
      switch modelSelection {
      case "":
        nil
      case ModelSelectionUI.customModelSentinel:
        customModel.trimmedNonEmpty
      default:
        modelSelection
      }
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case createTapped
    case createResponse(WuhuSession)
    case createFailed(String)
    case cancelTapped
    case delegate(Delegate)

    enum Delegate: Equatable {
      case created(WuhuSession)
      case cancelled
    }
  }

  @Dependency(\.apiClient) var apiClient

  var body: some ReducerOf<Self> {
    BindingReducer()

    Reduce { state, action in
      switch action {
      case .createTapped:
        state.isCreating = true
        state.error = nil
        let request = WuhuCreateSessionRequest(
          provider: state.provider,
          model: state.resolvedModelID,
          reasoningEffort: state.reasoningEffort,
        )
        return .run { send in
          let session = try await apiClient.createSession(request)
          await send(.createResponse(session))
        } catch: { error, send in
          await send(.createFailed("\(error)"))
        }

      case let .createResponse(session):
        state.isCreating = false
        return .send(.delegate(.created(session)))

      case let .createFailed(message):
        state.isCreating = false
        state.error = message
        return .none

      case .cancelTapped:
        return .send(.delegate(.cancelled))

      case let .binding(binding):
        state.error = nil
        if binding.keyPath == \.provider {
          state.modelSelection = ""
          state.customModel = ""
          state.reasoningEffort = nil
        }
        let supportedEfforts = WuhuModelCatalog.supportedReasoningEfforts(
          provider: state.provider, modelID: state.resolvedModelID,
        )
        if let current = state.reasoningEffort, !supportedEfforts.contains(current) {
          state.reasoningEffort = nil
        }
        return .none

      case .delegate:
        return .none
      }
    }
  }
}

// MARK: - View

struct CreateSessionView: View {
  @Bindable var store: StoreOf<CreateSessionFeature>

  var body: some View {
    NavigationStack {
      Form {
        Section("Model") {
          ModelSelectionFields(
            provider: $store.provider,
            modelSelection: $store.modelSelection,
            customModel: $store.customModel,
            reasoningEffort: $store.reasoningEffort,
          )
        }

        if let error = store.error {
          Section {
            Text(error)
              .foregroundStyle(.red)
              .font(.caption)
          }
        }
      }
      .formStyle(.grouped)
      .navigationTitle("New Session")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            store.send(.cancelTapped)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Create") {
            store.send(.createTapped)
          }
          .disabled(store.isCreating)
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 350, minHeight: 250)
    #endif
  }
}
