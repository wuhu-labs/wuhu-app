import ComposableArchitecture
import Foundation
import WorkspaceContracts

// MARK: - Docs Feature

@Reducer
struct DocsFeature {
  @ObservableState
  struct State: Equatable {
    /// The workspace directory tree, loaded from the server.
    var tree: DirectoryNode?

    /// Set of expanded directory paths in the sidebar tree.
    var expandedPaths: Set<String> = []

    /// The currently selected sidebar item. This determines what's shown in the
    /// detail pane.
    var selectedItem: SidebarItem?

    /// The path of the document currently displayed in the detail pane.
    /// This is the resolved workspace-relative path (e.g. "docs/_index.md").
    var currentDocPath: String?

    /// The loaded markdown body for the current document.
    var currentDocBody: String?

    /// Pre-fetched query results for wuhu-view blocks, keyed by SQL string.
    /// Populated when a doc containing wuhu-view code blocks is loaded.
    var queryResults: [String: [[String: String]]] = [:]

    /// Whether content is currently loading.
    var isLoading = false

    /// Error message if the last load failed.
    var loadError: String?
  }

  /// Represents a selectable item in the sidebar tree.
  enum SidebarItem: Equatable, Hashable {
    /// A directory — shows `_index.md` (or synthesized file list if no index).
    case directory(path: String)
    /// The "Files…" virtual item under a directory — shows `_files.md`.
    case files(path: String)
  }

  enum Action: Equatable {
    case treeLoaded(DirectoryNode)
    case treeLoadFailed(String)
    case toggleExpanded(String)
    case itemSelected(SidebarItem?)
    case docLoaded(path: String, body: String, queryResults: [String: [[String: String]]])
    case docLoadFailed(String)
    case linkTapped(url: URL)
  }

  @Dependency(\.apiClient) var apiClient

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .treeLoaded(tree):
        state.tree = tree
        // Auto-expand root children
        for child in tree.children {
          state.expandedPaths.insert(child.path)
        }
        // Auto-select root if nothing selected
        if state.selectedItem == nil {
          state.selectedItem = .directory(path: "")
          return loadDoc(state: &state, path: "_index.md")
        }
        return .none

      case let .treeLoadFailed(error):
        state.loadError = error
        return .none

      case let .toggleExpanded(path):
        if state.expandedPaths.contains(path) {
          state.expandedPaths.remove(path)
        } else {
          state.expandedPaths.insert(path)
        }
        return .none

      case let .itemSelected(item):
        state.selectedItem = item
        guard let item else {
          state.currentDocPath = nil
          state.currentDocBody = nil
          return .none
        }
        let docPath: String
        switch item {
        case let .directory(path):
          docPath = path.isEmpty ? "_index.md" : "\(path)/_index.md"
        case let .files(path):
          docPath = path.isEmpty ? "_files.md" : "\(path)/_files.md"
        }
        return loadDoc(state: &state, path: docPath)

      case let .docLoaded(path, body, queryResults):
        state.isLoading = false
        state.loadError = nil
        state.currentDocPath = path
        state.currentDocBody = body
        state.queryResults = queryResults
        return .none

      case let .docLoadFailed(error):
        state.isLoading = false
        state.loadError = error
        return .none

      case let .linkTapped(url):
        // External links — ignore, let the system handle them.
        if let scheme = url.scheme, scheme == "http" || scheme == "https" {
          return .none
        }

        let target = url.absoluteString

        // Resolve the link relative to the current document's directory.
        let resolvedPath = resolveDocLink(
          target: target,
          currentDocPath: state.currentDocPath
        )

        guard let resolvedPath else { return .none }

        // Update sidebar selection to match, if it's an _index.md or _files.md.
        let filename = resolvedPath.split(separator: "/").last.map(String.init) ?? resolvedPath
        let dirPath = directoryOf(resolvedPath)

        if filename == "_files.md" {
          state.selectedItem = .files(path: dirPath)
        } else if filename == "_index.md" {
          state.selectedItem = .directory(path: dirPath)
        }
        // For other .md files, we don't change sidebar selection — just load content.

        // Ensure the parent directory is expanded.
        if !dirPath.isEmpty {
          state.expandedPaths.insert(dirPath)
          // Also expand ancestors.
          var ancestor = directoryOf(dirPath)
          while !ancestor.isEmpty {
            state.expandedPaths.insert(ancestor)
            ancestor = directoryOf(ancestor)
          }
        }

        return loadDoc(state: &state, path: resolvedPath)
      }
    }
  }

  // MARK: - Helpers

  private func loadDoc(state: inout State, path: String) -> Effect<Action> {
    state.isLoading = true
    state.loadError = nil
    return .run { send in
      let doc = try await apiClient.readWorkspaceDoc(path)
      let body = doc.body

      // Flatten once to extract SQL queries from custom kanban blocks.
      // This is the same code path the view uses, so keys match exactly.
      let blocks = MarkdownFlattener.flatten(body, sectionID: path)
      var queryResults: [String: [[String: String]]] = [:]
      for block in blocks {
        if case .custom("kanban") = block.kind,
           case .custom(let content) = block.content,
           let sql = content.fields["sql"] {
          if let rows = try? await apiClient.workspaceQuery(sql) {
            queryResults[sql] = rows
          }
        }
      }

      await send(.docLoaded(path: path, body: body, queryResults: queryResults))
    } catch: { error, send in
      await send(.docLoadFailed(error.localizedDescription))
    }
  }
}

// MARK: - Path Resolution

/// Resolves a link target relative to the current document's directory.
///
/// Rules:
/// - `/path/to/doc.md` → absolute, resolved from workspace root
/// - `./doc.md` or `doc.md` → relative to current doc's directory
/// - `../other/doc.md` → relative with parent traversal
func resolveDocLink(target: String, currentDocPath: String?) -> String? {
  let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty else { return nil }

  // Absolute path — strip leading "/" and use as-is.
  if trimmed.hasPrefix("/") {
    let path = String(trimmed.dropFirst())
    return path.isEmpty ? nil : path
  }

  // Relative path — resolve against current doc's directory.
  let baseDir: String
  if let currentDocPath {
    baseDir = directoryOf(currentDocPath)
  } else {
    baseDir = ""
  }

  // Combine base directory with relative target.
  let combined = baseDir.isEmpty ? trimmed : "\(baseDir)/\(trimmed)"

  // Normalize: resolve `.` and `..` components.
  var components: [String] = []
  for component in combined.split(separator: "/") {
    switch component {
    case ".":
      continue
    case "..":
      if !components.isEmpty { components.removeLast() }
    default:
      components.append(String(component))
    }
  }

  let result = components.joined(separator: "/")
  return result.isEmpty ? nil : result
}

/// Returns the directory portion of a path (everything before the last "/").
/// Returns "" for root-level paths.
private func directoryOf(_ path: String) -> String {
  guard let lastSlash = path.lastIndex(of: "/") else { return "" }
  return String(path[path.startIndex..<lastSlash])
}
