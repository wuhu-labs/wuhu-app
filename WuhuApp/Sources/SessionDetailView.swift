import ComposableArchitecture
import SwiftUI
import WuhuAPI

// MARK: - Session Detail (detail column)

struct SessionDetailView: View {
  @Bindable var store: StoreOf<SessionFeature>

  var body: some View {
    Group {
      if store.isLoadingDetail {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let session = store.selectedSession {
        SessionThreadView(
          session: session,
          streamingText: store.streamingText,
          isRunning: store.executionStatus == .running,
          isStopping: store.isStopping,
          isRetrying: store.isRetrying,
          retryAttempt: store.retryAttempt,
          retryDelaySeconds: store.retryDelaySeconds,
          selectedLane: $store.selectedLane,
          steerBackfill: store.steer,
          followUpBackfill: store.followUp,
          pendingImages: store.pendingImages,
          isUploadingImages: store.isUploadingImages,
          onSend: { message in
            store.send(.sendMessage(message))
          },
          onStop: {
            store.send(.stopSessionTapped)
          },
          onAddImage: { data, mimeType in
            store.send(.addImage(data, mimeType))
          },
          onRemoveImage: { id in
            store.send(.removeImage(id))
          },
        )
      } else {
        ContentUnavailableView(
          "No Session Selected",
          systemImage: "terminal",
          description: Text("Select a session to view its thread"),
        )
      }
    }
    #if os(iOS)
    .toolbar {
      if store.selectedSession != nil {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("Model") {
            store.isShowingModelPicker = true
          }
        }
      }
    }
    #endif
    .sheet(isPresented: $store.isShowingModelPicker) {
      SessionModelPickerSheet(store: store)
    }
  }
}

// MARK: - Model Picker Sheet

private struct SessionModelPickerSheet: View {
  @Bindable var store: StoreOf<SessionFeature>

  var body: some View {
    NavigationStack {
      Form {
        if let status = store.modelUpdateStatus {
          Section {
            Text(status)
              .foregroundStyle(.secondary)
          }
        }

        if let error = store.subscriptionError {
          Section {
            Text(error)
              .foregroundStyle(.red)
          }
        }

        Section("Model") {
          ModelSelectionFields(
            provider: $store.provider,
            modelSelection: $store.modelSelection,
            customModel: $store.customModel,
            reasoningEffort: $store.reasoningEffort,
          )
        }

        Section {
          Button("Apply") { store.send(.applyModelTapped) }
            .disabled(store.isUpdatingModel)
        }
      }
      .formStyle(.grouped)
      .navigationTitle("Model")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            store.isShowingModelPicker = false
          }
        }
        if store.isUpdatingModel {
          ToolbarItem(placement: .confirmationAction) {
            ProgressView()
          }
        }
      }
    }
    #if os(macOS)
    .frame(minWidth: 350, minHeight: 300)
    #endif
  }
}
