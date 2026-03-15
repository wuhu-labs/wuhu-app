import ComposableArchitecture
import SwiftUI
import WorkspaceContracts
import WuhuDocView

// MARK: - Docs Sidebar (tree view)

struct DocsTreeView: View {
  @Bindable var store: StoreOf<DocsFeature>

  var body: some View {
    List(selection: $store.selectedItem.sending(\.itemSelected)) {
      if let tree = store.tree {
        // Root directory item
        DirectoryRow(
          label: tree.name.isEmpty ? "Workspace" : tree.name,
          path: tree.path,
          systemImage: "folder",
          store: store
        )
        .tag(DocsFeature.SidebarItem.directory(path: tree.path))

        FilesRow(path: tree.path)
          .tag(DocsFeature.SidebarItem.files(path: tree.path))

        // Root children
        ForEach(tree.children, id: \.path) { child in
          DirectoryTreeNode(node: child, store: store)
        }
      }
    }
    .listStyle(.sidebar)
    .navigationTitle("Docs")
  }
}

// MARK: - Recursive Tree Node

private struct DirectoryTreeNode: View {
  let node: DirectoryNode
  let store: StoreOf<DocsFeature>

  var body: some View {
    let isExpanded = store.expandedPaths.contains(node.path)

    DisclosureGroup(
      isExpanded: Binding(
        get: { isExpanded },
        set: { _ in store.send(.toggleExpanded(node.path)) }
      )
    ) {
      // "Files…" virtual item
      FilesRow(path: node.path)
        .tag(DocsFeature.SidebarItem.files(path: node.path))

      // Child directories
      ForEach(node.children, id: \.path) { child in
        DirectoryTreeNode(node: child, store: store)
      }
    } label: {
      DirectoryRow(
        label: node.name,
        path: node.path,
        systemImage: "folder",
        store: store
      )
      .tag(DocsFeature.SidebarItem.directory(path: node.path))
    }
  }
}

// MARK: - Row Views

private struct DirectoryRow: View {
  let label: String
  let path: String
  let systemImage: String
  let store: StoreOf<DocsFeature>

  var body: some View {
    Label(label, systemImage: systemImage)
      .font(.callout)
  }
}

private struct FilesRow: View {
  let path: String

  var body: some View {
    Label("Files\u{2026}", systemImage: "doc.on.doc")
      .font(.callout)
      .foregroundStyle(.secondary)
  }
}

// MARK: - Docs Detail (content pane)

struct DocsDetailView: View {
  let store: StoreOf<DocsFeature>

  var body: some View {
    VStack(spacing: 0) {
      // Breadcrumb bar — fixed at top
      if let path = store.currentDocPath {
        breadcrumb(path: path)
        Divider()
      }

      // Content
      if store.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let body = store.currentDocBody, let path = store.currentDocPath {
        docContent(path: path, body: body)
      } else if let error = store.loadError {
        ContentUnavailableView(
          "Failed to Load",
          systemImage: "exclamationmark.triangle",
          description: Text(error)
        )
      } else {
        ContentUnavailableView(
          "No Document Selected",
          systemImage: "doc.text",
          description: Text("Select a directory to view its contents")
        )
      }
    }
  }

  // MARK: - Breadcrumb

  private func breadcrumb(path: String) -> some View {
    HStack {
      Image(systemName: "doc.text")
        .font(.caption)
        .foregroundStyle(.tertiary)
      Text(path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(.bar)
  }

  // MARK: - Document Content

  @ViewBuilder
  private func docContent(path: String, body: String) -> some View {
    let queryResults = store.queryResults
    let document = MarkdownFlattener.buildSimpleDocument(
      id: path,
      markdownContent: body
    )
    DocView(document: document, customBlockView: { block in
        guard case .custom(let tag) = block.kind,
              case .custom(let content) = block.content
        else { return nil }
        switch tag {
        case "kanban":
          guard let sql = content.fields["sql"] else { return nil }
          let rows = queryResults[sql] ?? []
          let source = content.fields["_source"]
          return AnyView(KanbanBoardView(rows: rows, source: source))
        default:
          return nil
        }
      })
      .environment(\.openURL, OpenURLAction { url in
        // Intercept workspace-relative links
        if isWorkspaceLink(url) {
          store.send(.linkTapped(url: url))
          return .handled
        }
        return .systemAction
      })
  }
}

// MARK: - Link Detection

/// Returns true if a URL looks like a workspace-relative link rather than an
/// external HTTP(S) URL.
private func isWorkspaceLink(_ url: URL) -> Bool {
  // External links have http/https schemes.
  if let scheme = url.scheme, scheme == "http" || scheme == "https" {
    return false
  }
  // Links with no scheme, or file: scheme, that end in .md are workspace links.
  let path = url.absoluteString
  if path.hasSuffix(".md") { return true }
  // Relative paths starting with ./ or ../ are workspace links.
  if path.hasPrefix("./") || path.hasPrefix("../") || path.hasPrefix("/") { return true }
  return false
}
