import Dependencies
import Foundation
import IdentifiedCollections
import PiAI
import WorkspaceContracts
import WuhuAPI
import WuhuClient
import WuhuCoreClient

// MARK: - API Client Dependency

struct APIClient: Sendable {
  var listSessions: @Sendable (_ includeArchived: Bool) async throws -> [WuhuSession]
  var getSession: @Sendable (_ id: String) async throws -> WuhuGetSessionResponse
  var createSession: @Sendable (_ request: WuhuCreateSessionRequest) async throws -> WuhuSession
  var listWorkspaceDocs: @Sendable () async throws -> [WuhuWorkspaceDocSummary]
  var workspaceTree: @Sendable () async throws -> DirectoryNode
  var readWorkspaceDoc: @Sendable (_ path: String) async throws -> WuhuWorkspaceDoc
  var workspaceQuery: @Sendable (_ sql: String) async throws -> [[String: String]]
  var enqueue: @Sendable (_ sessionID: String, _ content: MessageContent, _ user: String?, _ lane: UserQueueLane) async throws -> String
  var uploadBlob: @Sendable (_ sessionID: String, _ data: Data, _ mimeType: String) async throws -> String
  var renameSession: @Sendable (_ sessionID: String, _ title: String) async throws -> WuhuRenameSessionResponse
  var archiveSession: @Sendable (_ sessionID: String) async throws -> WuhuArchiveSessionResponse
  var unarchiveSession: @Sendable (_ sessionID: String) async throws -> WuhuArchiveSessionResponse
  var stopSession: @Sendable (_ sessionID: String) async throws -> WuhuStopSessionResponse
  var setSessionModel: @Sendable (
    _ sessionID: String,
    _ provider: WuhuProvider,
    _ model: String?,
    _ reasoningEffort: ReasoningEffort?,
  ) async throws -> WuhuSetSessionModelResponse
}

// MARK: - Shared Base URL Holder

/// A sendable holder for the current workspace's base URL.
/// Updated by AppFeature when the active workspace changes.
final class BaseURLHolder: @unchecked Sendable {
  private let lock = NSLock()
  private var _url: URL

  init(_ url: URL) {
    _url = url
  }

  var url: URL {
    lock.lock()
    defer { lock.unlock() }
    return _url
  }

  func update(_ url: URL) {
    lock.lock()
    defer { lock.unlock() }
    _url = url
  }
}

/// Shared instance read by live API client and transport provider.
/// Initialised from the persisted active workspace (or legacy UserDefaults key).
let sharedBaseURL: BaseURLHolder = {
  let workspaces = _loadWorkspacesSync()
  let activeID = _loadActiveWorkspaceIDSync()
  let ws = workspaces.first(where: { $0.id == activeID }) ?? workspaces.first ?? .default
  let url = URL(string: ws.serverURL) ?? URL(string: "http://localhost:8080")!
  return BaseURLHolder(url)
}()

/// Non-MainActor helpers for the shared initialiser. Only used at process start.
private func _loadWorkspacesSync() -> [Workspace] {
  guard let data = UserDefaults.standard.data(forKey: "wuhuWorkspaces"),
        let ws = try? JSONDecoder().decode([Workspace].self, from: data),
        !ws.isEmpty
  else {
    return [.default]
  }
  return ws
}

private func _loadActiveWorkspaceIDSync() -> UUID? {
  guard let str = UserDefaults.standard.string(forKey: "wuhuActiveWorkspaceID") else { return nil }
  return UUID(uuidString: str)
}

extension APIClient: DependencyKey {
  static let liveValue: APIClient = {
    let makeClient: @Sendable () -> WuhuClient = {
      WuhuClient(baseURL: sharedBaseURL.url)
    }
    return APIClient(
      listSessions: { try await makeClient().listSessions(includeArchived: $0) },
      getSession: { try await makeClient().getSession(id: $0) },
      createSession: { try await makeClient().createSession($0) },
      listWorkspaceDocs: { try await makeClient().listWorkspaceDocs() },
      workspaceTree: { try await makeClient().workspaceTree() },
      readWorkspaceDoc: { try await makeClient().readWorkspaceDoc(path: $0) },
      workspaceQuery: { try await makeClient().workspaceQuery(sql: $0) },
      enqueue: { sessionID, content, user, lane in
        let clientLane: WuhuClient.EnqueueLane = switch lane {
        case .steer: .steer
        case .followUp: .followUp
        }
        return try await makeClient().enqueue(sessionID: sessionID, content: content, user: user, lane: clientLane)
      },
      uploadBlob: { sessionID, data, mimeType in
        try await makeClient().uploadBlob(sessionID: sessionID, data: data, mimeType: mimeType)
      },
      renameSession: { sessionID, title in
        try await makeClient().renameSession(id: sessionID, title: title)
      },
      archiveSession: { try await makeClient().archiveSession(sessionID: $0) },
      unarchiveSession: { try await makeClient().unarchiveSession(sessionID: $0) },
      stopSession: { try await makeClient().stopSession(sessionID: $0) },
      setSessionModel: { sessionID, provider, model, reasoningEffort in
        try await makeClient().setSessionModel(
          sessionID: sessionID, provider: provider, model: model, reasoningEffort: reasoningEffort,
        )
      },
    )
  }()

  static let previewValue = APIClient(
    listSessions: { _ in [] },
    getSession: { _ in
      WuhuGetSessionResponse(
        session: WuhuSession(
          id: "preview",
          provider: .anthropic,
          model: "claude-sonnet-4-6",
          createdAt: Date(),
          updatedAt: Date(),
          headEntryID: 0,
          tailEntryID: 0,
        ),
        transcript: [],
      )
    },
    createSession: { _ in
      WuhuSession(
        id: "preview",
        provider: .anthropic,
        model: "claude-sonnet-4-6",
        createdAt: Date(),
        updatedAt: Date(),
        headEntryID: 0,
        tailEntryID: 0,
      )
    },
    listWorkspaceDocs: { [] },
    workspaceTree: { DirectoryNode(path: "", name: "", children: [], hasIndex: false) },
    readWorkspaceDoc: { _ in WuhuWorkspaceDoc(path: "", frontmatter: [:], body: "") },
    workspaceQuery: { _ in [] },
    enqueue: { _, _, _, _ in "" },
    uploadBlob: { _, _, _ in "blob://preview/test.png" },
    renameSession: { _, _ in
      WuhuRenameSessionResponse(session: WuhuSession(
        id: "preview",
        provider: .anthropic,
        model: "claude-sonnet-4-6",
        createdAt: Date(),
        updatedAt: Date(),
        headEntryID: 0,
        tailEntryID: 0,
      ))
    },
    archiveSession: { _ in
      WuhuArchiveSessionResponse(session: WuhuSession(
        id: "preview",
        provider: .anthropic,
        model: "claude-sonnet-4-6",
        isArchived: true,
        createdAt: Date(),
        updatedAt: Date(),
        headEntryID: 0,
        tailEntryID: 0,
      ))
    },
    unarchiveSession: { _ in
      WuhuArchiveSessionResponse(session: WuhuSession(
        id: "preview",
        provider: .anthropic,
        model: "claude-sonnet-4-6",
        createdAt: Date(),
        updatedAt: Date(),
        headEntryID: 0,
        tailEntryID: 0,
      ))
    },
    stopSession: { _ in WuhuStopSessionResponse(repairedEntries: [], stopEntry: nil) },
    setSessionModel: { _, _, _, _ in
      WuhuSetSessionModelResponse(
        session: WuhuSession(
          id: "preview",
          provider: .anthropic,
          model: "claude-sonnet-4-6",
          createdAt: Date(),
          updatedAt: Date(),
          headEntryID: 0,
          tailEntryID: 0,
        ),
        selection: WuhuSessionSettings(provider: .anthropic, model: "claude-sonnet-4-6"),
        applied: true,
      )
    },
  )
}

extension DependencyValues {
  var apiClient: APIClient {
    get { self[APIClient.self] }
    set { self[APIClient.self] = newValue }
  }
}

// MARK: - Session Transport Provider

struct SessionTransportProvider: Sendable {
  var make: @Sendable () -> RemoteSessionSSETransport
}

extension SessionTransportProvider: DependencyKey {
  static let liveValue = SessionTransportProvider(
    make: { RemoteSessionSSETransport(baseURL: sharedBaseURL.url) },
  )
}

extension SessionTransportProvider: TestDependencyKey {
  static let testValue = SessionTransportProvider(
    make: { RemoteSessionSSETransport(baseURL: URL(string: "http://localhost:8080")!) },
  )
}

extension DependencyValues {
  var sessionTransportProvider: SessionTransportProvider {
    get { self[SessionTransportProvider.self] }
    set { self[SessionTransportProvider.self] = newValue }
  }
}

// MARK: - Transcript Conversion

enum TranscriptConverter {
  static func convertTranscript(
    _ entries: [WuhuSessionEntry],
    displayStartEntryID: Int64? = nil,
  ) -> [MockMessage] {
    let visibleEntries: [WuhuSessionEntry] = if let start = displayStartEntryID {
      entries.filter { $0.id >= start }
    } else {
      entries
    }

    // Build tool result lookup from tool_execution entries
    var toolResults: [String: WuhuToolExecution] = [:]
    for entry in visibleEntries {
      if case let .toolExecution(exec) = entry.payload, exec.phase == .end {
        toolResults[exec.toolCallId] = exec
      }
    }

    // Also build tool result lookup from toolResult messages
    var toolResultMessages: [String: String] = [:]
    for entry in visibleEntries {
      if case let .message(.toolResult(toolResult)) = entry.payload {
        let text = extractText(from: toolResult.content)
        if !text.isEmpty {
          toolResultMessages[toolResult.toolCallId] = text
        }
      }
    }

    var messages: [MockMessage] = []
    for entry in visibleEntries {
      guard case let .message(msg) = entry.payload else { continue }
      switch msg {
      case let .user(userMsg):
        let text = extractText(from: userMsg.content)
        let images = extractImages(from: userMsg.content)
        guard !text.isEmpty || !images.isEmpty else { continue }
        messages.append(MockMessage(
          id: "entry-\(entry.id)",
          role: .user,
          author: userMsg.user == WuhuUserMessage.unknownUser ? nil : userMsg.user,
          content: text,
          images: images,
          timestamp: userMsg.timestamp,
        ))

      case let .assistant(assistantMsg):
        let text = extractText(from: assistantMsg.content)
        let images = extractImages(from: assistantMsg.content)
        let toolCalls = assistantMsg.content.compactMap { block -> MockToolCall? in
          guard case let .toolCall(id, name, arguments) = block else { return nil }
          let resultText: String = if let exec = toolResults[id], let result = exec.result {
            jsonValueToString(result)
          } else if let msgResult = toolResultMessages[id] {
            msgResult
          } else {
            ""
          }
          return MockToolCall(
            id: id,
            name: name,
            arguments: formatArguments(arguments),
            result: resultText,
          )
        }
        if !text.isEmpty || !toolCalls.isEmpty || !images.isEmpty {
          messages.append(MockMessage(
            id: "entry-\(entry.id)",
            role: .assistant,
            content: text,
            images: images,
            timestamp: assistantMsg.timestamp,
            toolCalls: toolCalls,
          ))
        }

      case .toolResult, .customMessage, .unknown:
        break
      }
    }
    return messages
  }

  static func deriveSessionTitle(from entries: [WuhuSessionEntry]) -> String? {
    for entry in entries {
      if case let .message(.user(userMsg)) = entry.payload {
        let text = extractText(from: userMsg.content)
        if !text.isEmpty {
          return String(text.prefix(60))
        }
      }
    }
    return nil
  }

  static func sessionStatus(from response: WuhuGetSessionResponse) -> MockSession.SessionStatus {
    if let exec = response.inProcessExecution, exec.activePromptCount > 0 {
      return .running
    }
    let idleThreshold: TimeInterval = 3600
    if Date().timeIntervalSince(response.session.updatedAt) < idleThreshold {
      return .idle
    }
    return .stopped
  }

  private static func extractText(from content: [WuhuContentBlock]) -> String {
    content.compactMap { block -> String? in
      if case let .text(text, _) = block { return text }
      return nil
    }.joined()
  }

  private static func extractImages(from content: [WuhuContentBlock]) -> [MockImageAttachment] {
    content.compactMap { block -> MockImageAttachment? in
      if case let .image(blobURI, mimeType) = block {
        return MockImageAttachment(blobURI: blobURI, mimeType: mimeType)
      }
      return nil
    }
  }

  private static func formatArguments(_ args: JSONValue) -> String {
    switch args {
    case let .string(s):
      return s
    case let .object(dict):
      if let cmd = dict["command"], case let .string(s) = cmd { return s }
      if let path = dict["file_path"], case let .string(s) = path { return s }
      if let path = dict["path"], case let .string(s) = path { return s }
      return jsonValueToString(args).prefix(100).description
    default:
      return jsonValueToString(args).prefix(100).description
    }
  }

  private static func jsonValueToString(_ value: JSONValue) -> String {
    switch value {
    case .null: return "null"
    case let .bool(b): return String(b)
    case let .number(n): return String(n)
    case let .string(s): return s
    case let .array(arr): return "[\(arr.map { jsonValueToString($0) }.joined(separator: ", "))]"
    case let .object(dict):
      let pairs = dict.map { "\($0.key): \(jsonValueToString($0.value))" }
      return "{\(pairs.joined(separator: ", "))}"
    }
  }
}

// MARK: - Session Conversion

extension MockSession {
  static func from(_ session: WuhuSession, messages: [MockMessage] = []) -> MockSession {
    let idleThreshold: TimeInterval = 3600
    let status: SessionStatus = if Date().timeIntervalSince(session.updatedAt) < idleThreshold {
      .idle
    } else {
      .stopped
    }
    let displayTitle = session.customTitle
      ?? TranscriptConverter.deriveSessionTitle(from: [])
      ?? "Untitled"
    return MockSession(
      id: session.id,
      title: displayTitle,
      customTitle: session.customTitle,
      model: session.model,
      status: status,
      isArchived: session.isArchived,
      parentSessionID: session.parentSessionID,
      updatedAt: session.updatedAt,
      messages: messages,
    )
  }

  static func from(_ response: WuhuGetSessionResponse) -> MockSession {
    let messages = TranscriptConverter.convertTranscript(
      response.transcript,
      displayStartEntryID: nil,
    )
    let displayTitle = response.session.customTitle
      ?? TranscriptConverter.deriveSessionTitle(from: response.transcript)
      ?? "Untitled"
    let status = TranscriptConverter.sessionStatus(from: response)

    return MockSession(
      id: response.session.id,
      title: displayTitle,
      customTitle: response.session.customTitle,
      model: response.session.model,
      status: status,
      isArchived: response.session.isArchived,
      parentSessionID: response.session.parentSessionID,
      updatedAt: response.session.updatedAt,
      messages: messages,
    )
  }
}

// MARK: - Workspace Docs Conversion

extension MockDoc {
  static func from(_ summary: WuhuWorkspaceDocSummary) -> MockDoc {
    let title = summary.frontmatter["title"]?.stringValue
      ?? summary.path.components(separatedBy: "/").last ?? summary.path
    let tags = summary.frontmatter["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []

    return MockDoc(
      id: summary.path,
      title: title,
      tags: tags,
      updatedAt: Date(),
      markdownContent: "",
    )
  }

  static func from(_ doc: WuhuWorkspaceDoc) -> MockDoc {
    let title = doc.frontmatter["title"]?.stringValue
      ?? doc.path.components(separatedBy: "/").last ?? doc.path
    let tags = doc.frontmatter["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []

    return MockDoc(
      id: doc.path,
      title: title,
      tags: tags,
      updatedAt: Date(),
      markdownContent: doc.body,
    )
  }
}

// MARK: - JSONValue Helpers

extension JSONValue {
  var stringValue: String? {
    if case let .string(s) = self { return s }
    return nil
  }

  var arrayValue: [JSONValue]? {
    if case let .array(a) = self { return a }
    return nil
  }
}
