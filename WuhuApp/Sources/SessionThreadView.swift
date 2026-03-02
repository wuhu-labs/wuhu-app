import MarkdownUI
import SwiftUI
import WuhuCoreClient

// MARK: - Session Thread View

struct SessionThreadView: View {
  let session: MockSession
  var streamingText: String = ""
  var isRunning: Bool = false
  var isStopping: Bool = false
  var isRetrying: Bool = false
  var retryAttempt: Int = 0
  var retryDelaySeconds: Double = 0
  @Binding var selectedLane: UserQueueLane
  var steerBackfill: UserQueueBackfill?
  var followUpBackfill: UserQueueBackfill?
  var pendingImages: [PendingImage] = []
  var isUploadingImages: Bool = false
  var onSend: ((String) -> Void)?
  var onStop: (() -> Void)?
  var onAddImage: ((Data, String) -> Void)?
  var onRemoveImage: ((UUID) -> Void)?
  @State private var draft = ""

  var body: some View {
    VStack(spacing: 0) {
      // Status bar — full width
      HStack(spacing: 12) {
        Circle().fill(statusColor).frame(width: 8, height: 8)
        Text(session.title).font(.headline)
        Spacer()
        if isRetrying {
          HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
              .font(.caption2)
            Text("Retrying (\(String(format: "%.0f", retryDelaySeconds))s)")
              .font(.caption)
          }
          .foregroundStyle(.orange)
        }
        Text(session.model)
          .font(.caption)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.orange.opacity(0.12))
          .foregroundStyle(.orange)
          .clipShape(Capsule())
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.bar)

      Divider()

      // Centered content column
      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
              ForEach(session.messages) { message in
                SessionMessageView(message: message)
              }
              if !streamingText.isEmpty {
                agentStreamingView
              } else if isRunning {
                agentThinkingView
              }
              Color.clear
                .frame(height: 1)
                .id("bottom")
            }
            .padding(16)
          }
          #if os(iOS)
          .scrollDismissesKeyboard(.interactively)
          #endif
          .onChange(of: session.messages.count) {
            withAnimation {
              proxy.scrollTo("bottom", anchor: .bottom)
            }
          }
          .onChange(of: streamingText) {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
          .onAppear {
            proxy.scrollTo("bottom", anchor: .bottom)
          }
        }

        // Pending queues display
        PendingQueuesBar(
          steerBackfill: steerBackfill,
          followUpBackfill: followUpBackfill,
        )

        Divider()

        ChatInputField(
          draft: $draft,
          pendingImages: pendingImages,
          isUploadingImages: isUploadingImages,
          isRunning: isRunning,
          isStopping: isStopping,
          onSend: { sendDraft() },
          onStop: onStop,
          onAddImage: onAddImage,
          onRemoveImage: onRemoveImage,
        ) {
          Picker("", selection: $selectedLane) {
            Text("Steer").tag(UserQueueLane.steer)
            Text("Follow-up").tag(UserQueueLane.followUp)
          }
          .pickerStyle(.segmented)
          .frame(width: 160)
          .help(
            selectedLane == .steer
              ? "Steer: interrupts the agent at the next checkpoint"
              : "Follow-up: queued for after the agent finishes",
          )
        }
      }
      .frame(maxWidth: 800)
    }
  }

  private func sendDraft() {
    guard !draft.isEmpty || !pendingImages.isEmpty else { return }
    onSend?(draft)
    draft = ""
  }

  private var agentStreamingView: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text("Agent")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.purple)
        ProgressView()
          .controlSize(.mini)
      }
      Markdown(streamingText)
        .textSelection(.enabled)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var agentThinkingView: some View {
    HStack(spacing: 6) {
      Text("Agent")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.purple)
      ProgressView()
        .controlSize(.mini)
      Text("Working...")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var statusColor: Color {
    switch session.status {
    case .running: .green
    case .idle: .gray
    case .stopped: .red
    }
  }
}
