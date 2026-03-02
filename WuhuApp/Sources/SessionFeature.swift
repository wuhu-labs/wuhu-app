import ComposableArchitecture
import Foundation
import IdentifiedCollections
import PiAI
import WuhuAPI
import WuhuCoreClient

// MARK: - Pending Image

struct PendingImage: Identifiable, Equatable, Sendable {
  let id: UUID
  let data: Data
  let mimeType: String

  init(id: UUID = UUID(), data: Data, mimeType: String) {
    self.id = id
    self.data = data
    self.mimeType = mimeType
  }
}

@Reducer
struct SessionFeature {
  @ObservableState
  struct State {
    var sessions: IdentifiedArrayOf<MockSession> = []
    var selectedSessionID: String?
    var isLoadingDetail = false

    // Subscription state for the selected session
    var transcript: IdentifiedArrayOf<WuhuSessionEntry> = []
    var displayStartEntryID: Int64?
    var settings: SessionSettingsSnapshot?
    var status: SessionStatusSnapshot?
    var systemUrgent: SystemUrgentQueueBackfill?
    var steer: UserQueueBackfill?
    var followUp: UserQueueBackfill?

    /// Lane selection for enqueue
    var selectedLane: UserQueueLane = .followUp

    /// Archive state
    var showArchived = false

    // Rename state
    var isShowingRenameDialog = false
    var renameSessionID: String?
    var renameText: String = ""

    // Model picker state
    var provider: WuhuProvider = .anthropic
    var modelSelection: String = ""
    var customModel: String = ""
    var reasoningEffort: ReasoningEffort?
    var isShowingModelPicker = false
    var isUpdatingModel = false
    var modelUpdateStatus: String?

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

    /// Stop state
    var isStopping = false

    /// Streaming state
    var streamingText: String = ""

    // Connection state
    var isSubscribing = false
    var isRetrying = false
    var retryAttempt = 0
    var retryDelaySeconds: Double = 0
    var subscriptionError: String?

    // Image attachment state
    var pendingImages: [PendingImage] = []
    var isUploadingImages = false

    var selectedSession: MockSession? {
      guard let id = selectedSessionID else { return nil }
      return sessions[id: id]
    }

    var executionStatus: SessionExecutionStatus {
      status?.status ?? .idle
    }
  }

  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case sessionSelected(String?)
    case sessionInfoLoaded(WuhuGetSessionResponse)
    case sessionInfoFailed

    // Subscription lifecycle
    case startSubscription
    case subscriptionInitial(SessionInitialState)
    case subscriptionEvent(SessionEvent)
    case connectionStateChanged(SSEConnectionState)
    case subscriptionFailed(String)

    // Rename
    case renameMenuTapped(String)
    case renameConfirmed
    case renameCancelled
    case renameResponse(Result<WuhuRenameSessionResponse, any Error>)

    // Archive
    case archiveSession(String)
    case unarchiveSession(String)
    case archiveResponse(Result<WuhuArchiveSessionResponse, any Error>)
    case unarchiveResponse(Result<WuhuArchiveSessionResponse, any Error>)
    case toggleShowArchived

    // Stop
    case stopSessionTapped
    case stopSessionResponse(Result<WuhuStopSessionResponse, any Error>)

    // Commands
    case sendMessage(String)
    case enqueueSucceeded
    case enqueueFailed(String)

    // Image attachments
    case addImage(Data, String)
    case removeImage(UUID)

    // Model switching
    case applyModelTapped
    case setModelResponse(Result<WuhuSetSessionModelResponse, any Error>)
  }

  @Dependency(\.apiClient) var apiClient
  @Dependency(\.sessionTransportProvider) var sessionTransportProvider

  private enum CancelID {
    case subscription
  }

  var body: some ReducerOf<Self> {
    BindingReducer()

    Reduce { state, action in
      switch action {
      case let .binding(binding):
        if binding.keyPath == \State.provider {
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

      case let .sessionSelected(id):
        let previousID = state.selectedSessionID
        state.selectedSessionID = id
        state.subscriptionError = nil

        // Clear subscription state when deselecting or switching
        if id != previousID {
          state.transcript = []
          state.displayStartEntryID = nil
          state.settings = nil
          state.status = nil
          state.systemUrgent = nil
          state.steer = nil
          state.followUp = nil
          state.streamingText = ""
          state.isSubscribing = false
          state.isRetrying = false
        }

        guard let id else {
          state.isLoadingDetail = false
          return .cancel(id: CancelID.subscription)
        }

        state.isLoadingDetail = true
        return .merge(
          .cancel(id: CancelID.subscription),
          .run { send in
            let response = try await apiClient.getSession(id)
            await send(.sessionInfoLoaded(response))
          } catch: { _, send in
            await send(.sessionInfoFailed)
          },
        )

      case let .sessionInfoLoaded(response):
        state.isLoadingDetail = false

        // Update session in the list with messages from the REST response
        // (subscription will take over after this)
        let session = MockSession.from(response)
        state.sessions[id: session.id] = session

        return .send(.startSubscription)

      case .sessionInfoFailed:
        state.isLoadingDetail = false
        state.subscriptionError = "Failed to load session."
        return .none

      // MARK: - Subscription

      case .startSubscription:
        guard let sessionID = state.selectedSessionID else { return .none }

        state.isSubscribing = true
        state.isRetrying = false
        state.retryAttempt = 0
        state.retryDelaySeconds = 0
        state.subscriptionError = nil

        let since = makeSinceRequest(from: state)
        let transport = sessionTransportProvider.make()

        return .run { send in
          let result = try await transport.subscribeWithConnectionState(
            sessionID: .init(rawValue: sessionID),
            since: since,
          )
          await send(.subscriptionInitial(result.subscription.initial))

          await withTaskGroup(of: Void.self) { group in
            group.addTask {
              for await connectionState in result.connectionStates {
                await send(.connectionStateChanged(connectionState))
              }
            }
            group.addTask {
              do {
                for try await event in result.subscription.events {
                  await send(.subscriptionEvent(event))
                }
              } catch {
                if Task.isCancelled { return }
                await send(.subscriptionFailed("\(error)"))
              }
            }
            await group.waitForAll()
          }
        } catch: { error, send in
          if Task.isCancelled { return }
          await send(.subscriptionFailed("\(error)"))
        }
        .cancellable(id: CancelID.subscription, cancelInFlight: true)

      case let .subscriptionInitial(initial):
        state.isSubscribing = false
        state.settings = initial.settings
        state.status = initial.status
        state.systemUrgent = initial.systemUrgent
        state.steer = initial.steer
        state.followUp = initial.followUp

        let filtered: [WuhuSessionEntry] = if let start = state.displayStartEntryID {
          initial.transcript.filter { $0.id >= start }
        } else {
          initial.transcript
        }
        state.transcript = IdentifiedArray(uniqueElements: filtered)

        // Derive messages and update selected session
        updateSelectedSessionMessages(state: &state)

        // Update status from subscription
        if let status = state.status {
          updateSelectedSessionStatus(status, state: &state)
        }

        // Sync model picker from server settings
        syncModelSelectionFromSettings(initial.settings, state: &state)

        // Restore in-flight streaming text on (re)connection
        if let inflight = initial.inflightStreamText {
          state.streamingText = inflight
        } else {
          state.streamingText = ""
        }

        return .none

      case let .subscriptionEvent(event):
        state.subscriptionError = nil
        applyEvent(event, to: &state)

        if case .transcriptAppended = event {
          updateSelectedSessionMessages(state: &state)
        }
        if case let .statusUpdated(status) = event {
          updateSelectedSessionStatus(status, state: &state)
        }
        if case let .settingsUpdated(settings) = event {
          syncModelSelectionFromSettings(settings, state: &state)
          state.modelUpdateStatus = nil
        }

        return .none

      case let .connectionStateChanged(connectionState):
        switch connectionState {
        case .connecting:
          state.isSubscribing = true
          state.isRetrying = false
          state.retryAttempt = 0
          state.retryDelaySeconds = 0
        case .connected:
          state.isSubscribing = false
          state.isRetrying = false
          state.retryAttempt = 0
          state.retryDelaySeconds = 0
        case let .retrying(attempt, delaySeconds):
          state.isSubscribing = false
          state.isRetrying = true
          state.retryAttempt = attempt
          state.retryDelaySeconds = delaySeconds
        case .closed:
          state.isSubscribing = false
          state.isRetrying = false
        }
        return .none

      case let .subscriptionFailed(message):
        state.isSubscribing = false
        state.isRetrying = false
        state.subscriptionError = message
        return .none

      // MARK: - Rename

      case let .renameMenuTapped(sessionID):
        state.renameSessionID = sessionID
        state.renameText = state.sessions[id: sessionID]?.title ?? ""
        state.isShowingRenameDialog = true
        return .none

      case .renameConfirmed:
        guard let sessionID = state.renameSessionID else { return .none }
        let newTitle = state.renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        state.isShowingRenameDialog = false
        state.renameSessionID = nil

        guard !newTitle.isEmpty else { return .none }

        // Optimistically update
        state.sessions[id: sessionID]?.title = newTitle
        state.sessions[id: sessionID]?.customTitle = newTitle

        return .run { send in
          await send(
            .renameResponse(
              Result { try await apiClient.renameSession(sessionID, newTitle) },
            ),
          )
        }

      case .renameCancelled:
        state.isShowingRenameDialog = false
        state.renameSessionID = nil
        state.renameText = ""
        return .none

      case let .renameResponse(.success(response)):
        // Sync server's canonical title back
        let sessionID = response.session.id
        if let customTitle = response.session.customTitle {
          state.sessions[id: sessionID]?.title = customTitle
        }
        return .none

      case let .renameResponse(.failure(error)):
        state.subscriptionError = "Rename failed: \(error)"
        return .none

      // MARK: - Archive

      case let .archiveSession(sessionID):
        // Optimistically remove from visible list
        state.sessions[id: sessionID]?.isArchived = true
        if !state.showArchived {
          state.sessions.remove(id: sessionID)
          if state.selectedSessionID == sessionID {
            state.selectedSessionID = nil
          }
        }
        return .run { send in
          await send(
            .archiveResponse(
              Result { try await apiClient.archiveSession(sessionID) },
            ),
          )
        }

      case .archiveResponse(.success):
        return .none

      case let .archiveResponse(.failure(error)):
        state.subscriptionError = "Archive failed: \(error)"
        return .none

      case let .unarchiveSession(sessionID):
        state.sessions[id: sessionID]?.isArchived = false
        return .run { send in
          await send(
            .unarchiveResponse(
              Result { try await apiClient.unarchiveSession(sessionID) },
            ),
          )
        }

      case .unarchiveResponse(.success):
        return .none

      case let .unarchiveResponse(.failure(error)):
        state.subscriptionError = "Unarchive failed: \(error)"
        return .none

      case .toggleShowArchived:
        state.showArchived.toggle()
        return .none

      // MARK: - Stop

      case .stopSessionTapped:
        guard let sessionID = state.selectedSessionID else { return .none }
        guard !state.isStopping else { return .none }
        state.isStopping = true
        return .run { send in
          await send(
            .stopSessionResponse(
              Result { try await apiClient.stopSession(sessionID) },
            ),
          )
        }

      case .stopSessionResponse(.success):
        state.isStopping = false
        // The subscription will pick up the statusUpdated event.
        return .none

      case let .stopSessionResponse(.failure(error)):
        state.isStopping = false
        state.subscriptionError = "Stop failed: \(error)"
        return .none

      // MARK: - Commands

      case let .sendMessage(content):
        guard let sessionID = state.selectedSessionID else { return .none }

        let lane = state.selectedLane
        let pendingImages = state.pendingImages
        state.pendingImages = []
        state.isUploadingImages = !pendingImages.isEmpty

        // Optimistically add user message to the UI
        let username = UserDefaults.standard.string(forKey: "wuhuUsername")
        let trimmedUser = (username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        state.sessions[id: sessionID]?.messages.append(MockMessage(
          role: .user,
          author: trimmedUser.isEmpty ? nil : trimmedUser,
          content: content,
          timestamp: Date(),
        ))

        return .run { send in
          let user: String? = {
            let v = UserDefaults.standard.string(forKey: "wuhuUsername") ?? ""
            return v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : v
          }()

          // Upload images and build message content
          let messageContent: MessageContent
          if pendingImages.isEmpty {
            messageContent = .text(content)
          } else {
            var parts: [MessageContentPart] = []
            if !content.isEmpty {
              parts.append(.text(content))
            }
            for image in pendingImages {
              let blobURI = try await apiClient.uploadBlob(sessionID, image.data, image.mimeType)
              parts.append(.image(blobURI: blobURI, mimeType: image.mimeType))
            }
            messageContent = .richContent(parts)
          }

          _ = try await apiClient.enqueue(sessionID, messageContent, user, lane)
          await send(.enqueueSucceeded)
        } catch: { error, send in
          await send(.enqueueFailed("\(error)"))
        }

      case .enqueueSucceeded:
        state.isUploadingImages = false
        // The subscription will pick up the response via events
        return .none

      case let .enqueueFailed(message):
        state.isUploadingImages = false
        state.subscriptionError = message
        return .none

      // MARK: - Image Attachments

      case let .addImage(data, mimeType):
        state.pendingImages.append(PendingImage(data: data, mimeType: mimeType))
        return .none

      case let .removeImage(id):
        state.pendingImages.removeAll { $0.id == id }
        return .none

      // MARK: - Model Switching

      case .applyModelTapped:
        guard let sessionID = state.selectedSessionID else { return .none }
        state.isUpdatingModel = true
        state.modelUpdateStatus = nil

        let provider = state.provider
        let model = state.resolvedModelID
        let effort = state.reasoningEffort

        return .run { send in
          await send(
            .setModelResponse(
              Result {
                try await apiClient.setSessionModel(sessionID, provider, model, effort)
              },
            ),
          )
        }

      case let .setModelResponse(.success(response)):
        state.isUpdatingModel = false
        state.modelUpdateStatus = response.applied
          ? "Applied."
          : "Pending (will apply when session is idle)."
        return .none

      case let .setModelResponse(.failure(error)):
        state.isUpdatingModel = false
        state.subscriptionError = "\(error)"
        return .none
      }
    }
  }

  // MARK: - Helpers

  private func makeSinceRequest(from state: State) -> SessionSubscriptionRequest {
    let transcriptSince = state.transcript.last.map {
      TranscriptCursor(rawValue: String($0.id))
    }
    return SessionSubscriptionRequest(
      transcriptSince: transcriptSince,
      transcriptPageSize: 200,
      systemSince: state.systemUrgent?.cursor,
      steerSince: state.steer?.cursor,
      followUpSince: state.followUp?.cursor,
    )
  }

  private func applyEvent(_ event: SessionEvent, to state: inout State) {
    switch event {
    case let .transcriptAppended(entries):
      let filtered: [WuhuSessionEntry] = if let start = state.displayStartEntryID {
        entries.filter { $0.id >= start }
      } else {
        entries
      }
      for entry in filtered {
        state.transcript[id: entry.id] = entry
      }

    case let .systemUrgentQueue(cursor, entries):
      if var backfill = state.systemUrgent {
        backfill.cursor = cursor
        backfill.journal.append(contentsOf: entries)
        state.systemUrgent = backfill
      }

    case let .userQueue(cursor, entries):
      // Split entries by lane and apply to the correct backfill
      let steerEntries = entries.filter { $0.lane == .steer }
      let followUpEntries = entries.filter { $0.lane == .followUp }

      if !steerEntries.isEmpty {
        if var backfill = state.steer {
          backfill.cursor = cursor
          backfill.journal.append(contentsOf: steerEntries)
          Self.applyJournalEntriesToPending(steerEntries, pending: &backfill.pending)
          state.steer = backfill
        }
      }

      if !followUpEntries.isEmpty {
        if var backfill = state.followUp {
          backfill.cursor = cursor
          backfill.journal.append(contentsOf: followUpEntries)
          Self.applyJournalEntriesToPending(followUpEntries, pending: &backfill.pending)
          state.followUp = backfill
        }
      }

      // If all entries belong to one lane, still update cursor for the other backfills
      if steerEntries.isEmpty, var backfill = state.steer {
        backfill.cursor = cursor
        state.steer = backfill
      }
      if followUpEntries.isEmpty, var backfill = state.followUp {
        backfill.cursor = cursor
        state.followUp = backfill
      }

    case let .settingsUpdated(settings):
      state.settings = settings

    case let .statusUpdated(status):
      state.status = status

    case .streamBegan:
      state.streamingText = ""

    case let .streamDelta(delta):
      state.streamingText += delta

    case .streamEnded:
      state.streamingText = ""
    }
  }

  /// Apply journal entries to a pending items list:
  /// - `.enqueued` → insert the pending item
  /// - `.canceled` / `.materialized` → remove by id
  private static func applyJournalEntriesToPending(
    _ entries: [UserQueueJournalEntry],
    pending: inout [UserQueuePendingItem],
  ) {
    for entry in entries {
      switch entry {
      case let .enqueued(_, item):
        // Only add if not already present
        if !pending.contains(where: { $0.id == item.id }) {
          pending.append(item)
        }
      case let .canceled(_, id, _):
        pending.removeAll { $0.id == id }
      case let .materialized(_, id, _, _):
        pending.removeAll { $0.id == id }
      }
    }
  }

  private func updateSelectedSessionMessages(state: inout State) {
    guard let sessionID = state.selectedSessionID else { return }
    let messages = TranscriptConverter.convertTranscript(
      Array(state.transcript),
      displayStartEntryID: state.displayStartEntryID,
    )
    state.sessions[id: sessionID]?.messages = messages

    // Update title from transcript only when there is no user-supplied custom title
    if state.sessions[id: sessionID]?.customTitle == nil,
       let title = TranscriptConverter.deriveSessionTitle(from: Array(state.transcript))
    {
      state.sessions[id: sessionID]?.title = title
    }
  }

  private func syncModelSelectionFromSettings(_ settings: SessionSettingsSnapshot, state: inout State) {
    guard !state.isShowingModelPicker else { return }
    guard !state.isUpdatingModel else { return }

    state.provider = wuhuProviderFromSettings(settings)
    let model = settings.effectiveModel.id
    let knownIDs = Set(WuhuModelCatalog.models(for: state.provider).map(\.id))
    if knownIDs.contains(model) {
      state.modelSelection = model
      state.customModel = ""
    } else {
      state.modelSelection = ModelSelectionUI.customModelSentinel
      state.customModel = model
    }
    state.reasoningEffort = settings.effectiveReasoningEffort

    // Update session model display
    if let sessionID = state.selectedSessionID {
      state.sessions[id: sessionID]?.model = model
    }
  }

  private func wuhuProviderFromSettings(_ settings: SessionSettingsSnapshot) -> WuhuProvider {
    switch settings.effectiveModel.provider {
    case .openai: .openai
    case .openaiCodex: .openaiCodex
    case .anthropic: .anthropic
    default: .openai
    }
  }

  private func updateSelectedSessionStatus(_ status: SessionStatusSnapshot, state: inout State) {
    guard let sessionID = state.selectedSessionID else { return }
    let mockStatus: MockSession.SessionStatus = switch status.status {
    case .running: .running
    case .idle: .idle
    case .stopped: .stopped
    }
    state.sessions[id: sessionID]?.status = mockStatus
  }
}
