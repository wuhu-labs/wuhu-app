import MarkdownUI
import SwiftUI

// MARK: - Blob URL Helpers

enum BlobURLHelper {
  /// Parse a `blob://{sessionID}/{filename}` URI and build an HTTP serve URL.
  static func httpURL(for blobURI: String) -> URL? {
    // blob://{sessionID}/{filename}
    guard blobURI.hasPrefix("blob://") else { return nil }
    let path = String(blobURI.dropFirst("blob://".count))
    let components = path.split(separator: "/", maxSplits: 1)
    guard components.count == 2 else { return nil }
    let sessionID = String(components[0])
    let filename = String(components[1])
    return sharedBaseURL.url
      .appending(path: "v1")
      .appending(path: "sessions")
      .appending(path: sessionID)
      .appending(path: "blobs")
      .appending(path: filename)
  }
}

// MARK: - Blob Image View

struct BlobImageView: View {
  let blobURI: String

  var body: some View {
    if let url = BlobURLHelper.httpURL(for: blobURI) {
      AsyncImage(url: url) { phase in
        switch phase {
        case .empty:
          ProgressView()
            .frame(width: 120, height: 80)
        case let .success(image):
          image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 400, maxHeight: 300)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        case .failure:
          Image(systemName: "photo.badge.exclamationmark")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(width: 120, height: 80)
        @unknown default:
          EmptyView()
        }
      }
    } else {
      Image(systemName: "photo.badge.exclamationmark")
        .font(.title)
        .foregroundStyle(.secondary)
        .frame(width: 120, height: 80)
    }
  }
}

// MARK: - Session Message View

struct SessionMessageView: View {
  let message: MockMessage

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      switch message.role {
      case .user:
        userMessage
      case .assistant:
        assistantMessage
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var userMessage: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(message.author ?? "User")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.orange)
        Text(message.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      if !message.content.isEmpty {
        Text(message.content)
          .font(.body)
          .textSelection(.enabled)
          .padding(10)
          .background(.orange.opacity(0.08))
          .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      if !message.images.isEmpty {
        imageGrid(message.images)
      }
    }
  }

  private var assistantMessage: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text("Agent")
          .font(.caption)
          .fontWeight(.semibold)
          .foregroundStyle(.purple)
        Text(message.timestamp, style: .time)
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Markdown(message.content)
        .textSelection(.enabled)

      if !message.images.isEmpty {
        imageGrid(message.images)
      }

      ForEach(message.toolCalls) { tc in
        ToolCallRow(toolCall: tc)
      }
    }
  }

  private func imageGrid(_ images: [MockImageAttachment]) -> some View {
    FlowLayout(spacing: 8) {
      ForEach(images) { img in
        BlobImageView(blobURI: img.blobURI)
      }
    }
  }
}

/// A simple horizontal-wrapping layout for image thumbnails.
struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
    layout(in: proposal.width ?? .infinity, subviews: subviews).size
  }

  func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
    let result = layout(in: bounds.width, subviews: subviews)
    for (index, offset) in result.offsets.enumerated() {
      subviews[index].place(
        at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
        proposal: .unspecified,
      )
    }
  }

  private struct LayoutResult {
    var offsets: [CGPoint]
    var size: CGSize
  }

  private func layout(in maxWidth: CGFloat, subviews: Subviews) -> LayoutResult {
    var offsets: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxX: CGFloat = 0

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth, x > 0 {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      offsets.append(CGPoint(x: x, y: y))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
      maxX = max(maxX, x - spacing)
    }

    return LayoutResult(offsets: offsets, size: CGSize(width: maxX, height: y + rowHeight))
  }
}

// MARK: - Tool Call Row

struct ToolCallRow: View {
  let toolCall: MockToolCall
  @State private var isExpanded = false

  private var hasOutput: Bool {
    !toolCall.result.isEmpty
  }

  var body: some View {
    if hasOutput {
      DisclosureGroup(isExpanded: $isExpanded) {
        Text(toolCall.result)
          .font(.system(.caption, design: .monospaced))
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .padding(8)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.black.opacity(0.04))
          .clipShape(RoundedRectangle(cornerRadius: 4))
      } label: {
        toolCallLabel
      }
      .tint(.secondary)
      .padding(.vertical, 2)
    } else {
      toolCallLabel
        .padding(.vertical, 2)
    }
  }

  private var toolCallLabel: some View {
    HStack(spacing: 6) {
      Image(systemName: "gearshape")
        .font(.caption2)
        .foregroundStyle(.orange)
      Text(toolCall.name)
        .font(.system(.caption, design: .monospaced))
        .fontWeight(.medium)
        .lineLimit(1)
        .layoutPriority(1)
      Text(toolCall.arguments)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
  }
}
