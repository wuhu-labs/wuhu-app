import SwiftUI

// MARK: - Kanban Board View

/// A pure, synchronous kanban board that renders pre-fetched query results
/// grouped into columns.
///
/// Expects rows with columns: `filepath`, `title`, `group`.
/// Data is pre-fetched by `DocsFeature` so this view measures correctly
/// in the `WuhuDocView` collection view layout.
struct KanbanBoardView: View {
  let columns: [KanbanColumn]
  let source: String?

  @State private var showingSource = false

  init(rows: [[String: String]], source: String? = nil) {
    self.columns = KanbanColumn.from(rows: rows)
    self.source = source
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Toolbar
      HStack {
        Spacer()
        if source != nil {
          Button {
            showingSource = true
          } label: {
            Label("View Source", systemImage: "chevron.left.forwardslash.chevron.right")
              .font(.system(size: 11))
          }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .popover(isPresented: $showingSource) {
            sourcePopover
          }
        }
      }
      .padding(.bottom, 6)

      // Board
      if columns.isEmpty {
        Text("No items found")
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, minHeight: 80)
      } else {
        KanbanColumnsView(columns: columns)
      }
    }
  }

  @ViewBuilder
  private var sourcePopover: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("View Source")
          .font(.system(size: 12, weight: .semibold))
        Spacer()
        Button { showingSource = false } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
      }

      ScrollView {
        Text(source ?? "")
          .font(.system(size: 11, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxHeight: 300)
    }
    .padding(12)
    .frame(width: 400)
  }
}

// MARK: - Data Model

struct KanbanCard: Identifiable {
  var id: String { filepath }
  var filepath: String
  var title: String
}

struct KanbanColumn: Identifiable {
  var id: String { name }
  var name: String
  var cards: [KanbanCard]

  /// Groups raw query rows into ordered columns.
  /// Preserves the order of first appearance of each group value.
  static func from(rows: [[String: String]]) -> [KanbanColumn] {
    var columnOrder: [String] = []
    var cardsByGroup: [String: [KanbanCard]] = [:]

    for row in rows {
      let group = row["group"] ?? "Ungrouped"
      let filepath = row["filepath"] ?? ""
      let title = row["title"] ?? filepath

      if cardsByGroup[group] == nil {
        columnOrder.append(group)
      }
      cardsByGroup[group, default: []].append(
        KanbanCard(filepath: filepath, title: title)
      )
    }

    return columnOrder.map { name in
      KanbanColumn(name: name, cards: cardsByGroup[name] ?? [])
    }
  }
}

// MARK: - Column Layout

private struct KanbanColumnsView: View {
  let columns: [KanbanColumn]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(alignment: .top, spacing: 12) {
        ForEach(columns) { column in
          KanbanColumnView(column: column)
        }
      }
      .padding(.vertical, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct KanbanColumnView: View {
  let column: KanbanColumn

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Column header
      HStack(spacing: 6) {
        Text(column.name.capitalized)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
        Text("\(column.cards.count)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(.quaternary)
          .clipShape(Capsule())
      }
      .padding(.horizontal, 10)

      // Cards
      VStack(spacing: 6) {
        ForEach(column.cards) { card in
          KanbanCardView(card: card)
        }
      }
    }
    .frame(width: 200)
  }
}

private struct KanbanCardView: View {
  let card: KanbanCard

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(card.title)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.primary)
        .lineLimit(3)

      Text(card.filepath)
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .lineLimit(1)
        .truncationMode(.middle)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background.secondary)
    .clipShape(RoundedRectangle(cornerRadius: 6))
  }
}
