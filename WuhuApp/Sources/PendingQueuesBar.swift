import SwiftUI
import WuhuCoreClient

// MARK: - Pending Queues Bar

struct PendingQueuesBar: View {
  var steerBackfill: UserQueueBackfill?
  var followUpBackfill: UserQueueBackfill?

  private var steerPending: [UserQueuePendingItem] {
    steerBackfill?.pending ?? []
  }

  private var followUpPending: [UserQueuePendingItem] {
    followUpBackfill?.pending ?? []
  }

  private var hasPending: Bool {
    !steerPending.isEmpty || !followUpPending.isEmpty
  }

  var body: some View {
    if hasPending {
      VStack(alignment: .leading, spacing: 6) {
        if !steerPending.isEmpty {
          PendingQueueSection(title: "Steer Queue", items: steerPending, color: .red)
        }
        if !followUpPending.isEmpty {
          PendingQueueSection(title: "Follow-up Queue", items: followUpPending, color: .blue)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .background(.bar)
    }
  }
}

private struct PendingQueueSection: View {
  let title: String
  let items: [UserQueuePendingItem]
  let color: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Circle()
          .fill(color)
          .frame(width: 6, height: 6)
        Text("\(title) (\(items.count))")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(color)
      }
      ForEach(items, id: \.id) { item in
        Text(pendingItemPreview(item))
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .padding(.leading, 10)
      }
    }
  }

  private func pendingItemPreview(_ item: UserQueuePendingItem) -> String {
    switch item.message.content {
    case let .text(text):
      return String(text.prefix(80))
    case let .richContent(parts):
      let text = parts.compactMap { part -> String? in
        if case let .text(t) = part { return t }
        return nil
      }.joined()
      return String(text.prefix(80))
    }
  }
}
