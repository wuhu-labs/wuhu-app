import Foundation
import IdentifiedCollections

// MARK: - Mock Models

struct MockSession: Identifiable, Equatable {
  let id: String
  var title: String
  /// When non-nil, this is a user-supplied title that should take priority over auto-derived titles.
  var customTitle: String?
  var model: String
  var status: SessionStatus
  var isArchived: Bool = false
  /// Non-nil when this session was spawned by another session (child/forked).
  var parentSessionID: String?
  var updatedAt: Date
  var messages: [MockMessage]

  enum SessionStatus: String, Equatable {
    case running, idle, stopped
  }

  var lastMessagePreview: String {
    guard let last = messages.last else { return "No messages yet" }
    let prefix = last.role == .assistant ? "Agent" : last.author ?? "User"
    return "\(prefix): \(last.content.prefix(80))"
  }
}

/// An image attachment displayed inline in a message.
struct MockImageAttachment: Identifiable, Equatable {
  let id: String
  /// The blob URI, e.g. `blob://{sessionID}/{filename}`.
  var blobURI: String
  var mimeType: String

  init(id: String = UUID().uuidString, blobURI: String, mimeType: String) {
    self.id = id
    self.blobURI = blobURI
    self.mimeType = mimeType
  }
}

struct MockMessage: Identifiable, Equatable {
  let id: String
  var role: Role
  var author: String?
  var content: String
  var images: [MockImageAttachment]
  var timestamp: Date
  var toolCalls: [MockToolCall]

  enum Role: Equatable {
    case user
    case assistant
  }

  init(
    id: String = UUID().uuidString,
    role: Role,
    author: String? = nil,
    content: String,
    images: [MockImageAttachment] = [],
    timestamp: Date,
    toolCalls: [MockToolCall] = [],
  ) {
    self.id = id
    self.role = role
    self.author = author
    self.content = content
    self.images = images
    self.timestamp = timestamp
    self.toolCalls = toolCalls
  }
}

struct MockToolCall: Identifiable, Equatable {
  let id: String
  var name: String
  var arguments: String
  var result: String
}

struct MockDoc: Identifiable, Equatable {
  let id: String
  var title: String
  var tags: [String]
  var updatedAt: Date
  var markdownContent: String
}

// MARK: - Static Mock Data

enum MockData {
  static let workspaceName = "Isofucius Inc."

  // MARK: Sessions

  static let sessions: IdentifiedArrayOf<MockSession> = [
    MockSession(
      id: "s-001",
      title: "Fix auth token refresh",
      model: "claude-sonnet-4-6",
      status: .running,
      updatedAt: Date().addingTimeInterval(-120),
      messages: authSessionMessages,
    ),
    MockSession(
      id: "s-002",
      title: "Add WebSocket reconnection logic",
      model: "claude-opus-4-6",
      status: .running,
      updatedAt: Date().addingTimeInterval(-300),
      messages: websocketSessionMessages,
    ),
    MockSession(
      id: "s-003",
      title: "Refactor database migrations",
      model: "gpt-5",
      status: .idle,
      updatedAt: Date().addingTimeInterval(-43200),
      messages: [
        MockMessage(role: .user, author: "yihan", content: "Can you refactor the DB migrations to use the new GRDB migration API?", timestamp: Date().addingTimeInterval(-50000)),
        MockMessage(role: .assistant, content: "I'll update the migration system. Let me check the current setup first.", timestamp: Date().addingTimeInterval(-49900)),
      ],
    ),
    MockSession(
      id: "s-004",
      title: "Debug CI pipeline failure",
      model: "claude-sonnet-4-6",
      status: .stopped,
      updatedAt: Date().addingTimeInterval(-86400),
      messages: [
        MockMessage(role: .user, author: "kesou", content: "CI is failing on main. Can you check what's going on?", timestamp: Date().addingTimeInterval(-90000)),
        MockMessage(role: .assistant, content: "Let me look at the CI logs.", timestamp: Date().addingTimeInterval(-89900), toolCalls: [
          MockToolCall(id: "tc-ci-1", name: "bash", arguments: "gh run list --limit 5", result: "ID  STATUS  TITLE\n847 failure  main\n846 success main"),
        ]),
        MockMessage(role: .assistant, content: "Build #847 failed due to a Swift 6 concurrency error in `SessionStore.swift`. The `nonisolated` access to a mutable property was flagged.", timestamp: Date().addingTimeInterval(-89800)),
        MockMessage(role: .user, author: "minsheng", content: "That's the strict concurrency stuff. Can you add the Sendable conformance?", timestamp: Date().addingTimeInterval(-89700)),
        MockMessage(role: .assistant, content: "Done. Added `@unchecked Sendable` to `SessionStore` and wrapped the mutable state in a lock. CI should pass now.", timestamp: Date().addingTimeInterval(-89600)),
      ],
    ),
    MockSession(
      id: "s-005",
      title: "Implement environment resolver",
      model: "claude-opus-4-6",
      status: .idle,
      updatedAt: Date().addingTimeInterval(-172_800),
      messages: [
        MockMessage(role: .user, author: "anna", content: "We need a resolver that maps environment names to definitions. Start with local and folder-template types.", timestamp: Date().addingTimeInterval(-180_000)),
        MockMessage(role: .assistant, content: "I'll build the environment resolver. This needs to handle both static definitions and dynamic template instantiation.", timestamp: Date().addingTimeInterval(-179_900)),
      ],
    ),
    MockSession(
      id: "s-006",
      title: "Write API documentation",
      model: "gpt-5",
      status: .idle,
      updatedAt: Date().addingTimeInterval(-259_200),
      messages: [],
    ),
    MockSession(
      id: "s-007",
      title: "Optimize query performance",
      model: "claude-haiku-4-5",
      status: .stopped,
      updatedAt: Date().addingTimeInterval(-345_600),
      messages: [],
    ),
    MockSession(
      id: "s-008",
      title: "Add runner health checks",
      model: "claude-sonnet-4-6",
      status: .idle,
      updatedAt: Date().addingTimeInterval(-432_000),
      messages: [],
    ),
  ]

  // MARK: Detailed Session Messages

  private static let authSessionMessages: [MockMessage] = [
    MockMessage(
      role: .user, author: "minsheng",
      content: "The auth token refresh is failing silently. When the access token expires, the refresh request returns 401 but we're not handling it. Can you investigate and fix?",
      timestamp: Date().addingTimeInterval(-3600),
    ),
    MockMessage(
      role: .assistant,
      content: "I'll look into the auth token refresh logic. Let me start by reading the current implementation.",
      timestamp: Date().addingTimeInterval(-3550),
      toolCalls: [
        MockToolCall(
          id: "tc-1", name: "read_file",
          arguments: "Sources/WuhuClient/Auth.swift",
          result: "struct AuthManager {\n  func refreshToken() async throws -> Token {\n    let response = try await httpClient.post(\"/auth/refresh\", body: refreshBody)\n    return try decoder.decode(Token.self, from: response.body)\n  }\n}",
        ),
      ],
    ),
    MockMessage(
      role: .assistant,
      content: "I see the issue — `refreshToken()` doesn't check the HTTP status before decoding. A 401 body isn't a valid `Token`, so `decode` throws, but the error gets swallowed. Let me check the call site.",
      timestamp: Date().addingTimeInterval(-3500),
      toolCalls: [
        MockToolCall(
          id: "tc-2", name: "bash",
          arguments: "grep -rn \"refreshToken\" Sources/",
          result: "Sources/WuhuClient/Auth.swift:24:  func refreshToken()\nSources/WuhuClient/HTTPClient.swift:87:      try await authManager.refreshToken()\nSources/WuhuClient/HTTPClient.swift:91:      // retry original request",
        ),
        MockToolCall(
          id: "tc-3", name: "read_file",
          arguments: "Sources/WuhuClient/HTTPClient.swift:80-100",
          result: "  private func executeWithRetry(_ request: Request) async throws -> Response {\n    let response = try await execute(request)\n    if response.status == .unauthorized {\n      try await authManager.refreshToken()\n      return try await execute(request)\n    }\n    return response\n  }",
        ),
      ],
    ),
    MockMessage(
      role: .user, author: "anna",
      content: "Yeah I hit this too. The retry also doesn't distinguish between \"original 401\" vs \"refresh itself got 401\" — if the refresh token is expired we'd loop.",
      timestamp: Date().addingTimeInterval(-3450),
    ),
    MockMessage(
      role: .assistant,
      content: "Exactly right. The fix is:\n\n1. Add status code checking in `refreshToken()` \n2. Throw `AuthError.refreshTokenExpired` when refresh endpoint returns 401\n3. In `executeWithRetry`, catch that specific error and propagate instead of retrying\n\nImplementing now.",
      timestamp: Date().addingTimeInterval(-3400),
      toolCalls: [
        MockToolCall(
          id: "tc-4", name: "edit_file",
          arguments: "Sources/WuhuClient/Auth.swift",
          result: "Applied 2 edits to Auth.swift",
        ),
        MockToolCall(
          id: "tc-5", name: "edit_file",
          arguments: "Sources/WuhuClient/HTTPClient.swift",
          result: "Applied 1 edit to HTTPClient.swift",
        ),
        MockToolCall(
          id: "tc-6", name: "bash",
          arguments: "swift test --filter AuthTests 2>&1 | tail -5",
          result: "Test Suite 'AuthTests' passed.\n Executed 4 tests, with 0 failures in 0.832 seconds",
        ),
      ],
    ),
    MockMessage(
      role: .user, author: "kesou",
      content: "Looks clean. What about the case where the network is down entirely during refresh?",
      timestamp: Date().addingTimeInterval(-3350),
    ),
    MockMessage(
      role: .assistant,
      content: "Good catch — network errors during refresh will now propagate as `AuthError.networkError(underlying:)` instead of being silently swallowed. The caller can retry or show a connectivity alert. All 4 auth tests pass.",
      timestamp: Date().addingTimeInterval(-3300),
    ),
    MockMessage(
      role: .user, author: "minsheng",
      content: "Ship it.",
      timestamp: Date().addingTimeInterval(-3200),
    ),
  ]

  private static let websocketSessionMessages: [MockMessage] = [
    MockMessage(
      role: .user, author: "anna",
      content: "The WebSocket connection drops when the laptop sleeps and doesn't reconnect. Add exponential backoff reconnection.",
      timestamp: Date().addingTimeInterval(-7200),
    ),
    MockMessage(
      role: .assistant,
      content: "I'll add reconnection logic. Let me check the current WebSocket implementation.",
      timestamp: Date().addingTimeInterval(-7150),
      toolCalls: [
        MockToolCall(
          id: "tc-ws-1", name: "read_file",
          arguments: "Sources/WuhuClient/WebSocketTransport.swift",
          result: "actor WebSocketTransport {\n  private var connection: WebSocket?\n  \n  func connect(to url: URL) async throws {\n    connection = try await WebSocket.connect(to: url)\n  }\n}",
        ),
      ],
    ),
    MockMessage(
      role: .assistant,
      content: "No reconnection logic at all. I'll add a manager with exponential backoff (1s → 2s → 4s → 8s, capped at 30s) and jitter to avoid thundering herd.",
      timestamp: Date().addingTimeInterval(-7100),
      toolCalls: [
        MockToolCall(
          id: "tc-ws-2", name: "edit_file",
          arguments: "Sources/WuhuClient/WebSocketTransport.swift",
          result: "Applied 3 edits — added ReconnectionManager, backoff logic, and connection state observer",
        ),
      ],
    ),
    MockMessage(
      role: .user, author: "yihan",
      content: "Should we also handle the case where the server actively closes the connection with a close frame? That's different from a network drop.",
      timestamp: Date().addingTimeInterval(-7000),
    ),
    MockMessage(
      role: .assistant,
      content: "Yes — I'll distinguish between:\n- **Network drop**: reconnect with backoff\n- **Server close (1000 Normal)**: don't reconnect\n- **Server close (1001 Going Away)**: reconnect immediately (server is restarting)\n- **Server close (other)**: reconnect with backoff",
      timestamp: Date().addingTimeInterval(-6900),
      toolCalls: [
        MockToolCall(
          id: "tc-ws-3", name: "bash",
          arguments: "swift test --filter WebSocketTests",
          result: "Test Suite 'WebSocketTests' passed.\n Executed 7 tests, with 0 failures in 1.204 seconds",
        ),
      ],
    ),
    MockMessage(
      role: .user, author: "anna",
      content: "Perfect, merging.",
      timestamp: Date().addingTimeInterval(-6800),
    ),
  ]

  // MARK: Docs

  static let docs: IdentifiedArrayOf<MockDoc> = [
    MockDoc(
      id: "doc-1", title: "Architecture Overview",
      tags: ["architecture", "reference"],
      updatedAt: Date().addingTimeInterval(-86400),
      markdownContent: """
      # Architecture Overview

      Wuhu is built around a **client-server architecture** with support for multiple environments and runners.

      ## Core Components

      - **Server** — Manages sessions, entries, and environment lifecycle. Built with [Hummingbird](https://github.com/hummingbird-project/hummingbird).
      - **Client** — HTTP + WebSocket client for interacting with the server.
      - **Runner** — Executes tool calls in isolated environments. Communicates via WebSocket.
      - **CLI** — Command-line interface for session management.

      ## Data Flow

      ```
      User Input → Session → Agent Loop → Tool Execution → Entry Storage
      ```

      Sessions maintain an **append-only log** of entries. Each entry contains a payload (message, tool execution, compaction, etc.) and links to its parent entry for branching support.

      ## Environment Types

      | Type | Description |
      |------|-------------|
      | `local` | Runs in the user's local directory |
      | `folder-template` | Creates isolated copies from a template |

      ## Key Design Decisions

      1. **Append-only entries** — Enables branching, forking, and full history replay without data loss.
      2. **Snapshot environments** — Sessions capture environment state at creation for reproducibility.
      3. **Provider-agnostic** — Supports OpenAI, Anthropic, and is extensible to other providers.
      4. **Multi-agent sessions** — Multiple users and agents can participate in a single session thread.

      ## Session Lifecycle

      ```
      Created → Running → Idle
                  ↓
               Stopped
      ```

      A session starts in `Created` state, moves to `Running` when the agent loop begins processing, returns to `Idle` when waiting for input, and can be `Stopped` manually or on error.
      """,
    ),
    MockDoc(
      id: "doc-2", title: "API Reference",
      tags: ["api", "reference"],
      updatedAt: Date().addingTimeInterval(-172_800),
      markdownContent: """
      # API Reference

      Base URL: `http://localhost:8080/api/v1`

      ## Sessions

      ### `POST /sessions`

      Create a new session.

      **Request Body:**
      ```json
      {
        "provider": "anthropic",
        "model": "claude-sonnet-4-6"
      }
      ```

      ### `GET /sessions/:id`

      Get session with full transcript.

      ### `POST /sessions/:id/messages`

      Send a user message to a session.

      **Request Body:**
      ```json
      {
        "content": "Fix the auth token refresh bug"
      }
      ```

      ### `GET /sessions/:id/stream`

      Stream session events via **Server-Sent Events** (SSE).

      Event types:
      - `entryAppended` — New entry added to transcript
      - `assistantTextDelta` — Streaming text from the model
      - `idle` — Agent is waiting for input
      - `done` — Session processing complete

      ## Mount Templates

      ### `GET /mount-templates`

      List all available mount templates.

      ### `POST /mount-templates`

      Create a new mount template.
      """,
    ),
    MockDoc(
      id: "doc-3", title: "Getting Started",
      tags: ["guide", "onboarding"],
      updatedAt: Date().addingTimeInterval(-259_200),
      markdownContent: """
      # Getting Started with Wuhu

      ## Prerequisites

      - macOS 15+
      - Swift 6.0+ toolchain
      - An API key (Anthropic or OpenAI)

      ## Installation

      ```bash
      git clone https://github.com/isofucius/wuhu-swift
      cd wuhu-swift
      swift build
      ```

      ## Running the Server

      ```bash
      swift run wuhu serve --port 8080
      ```

      You should see:
      ```
      [INFO] Server started on http://localhost:8080
      ```

      ## Creating Your First Session

      In another terminal:

      ```bash
      swift run wuhu session new --model claude-sonnet-4-6
      ```

      This creates a new coding session using Claude Sonnet.

      ## Next Steps

      - Read the **Architecture Overview** to understand the system design
      - Check the **API Reference** for programmatic access
      """,
    ),
    MockDoc(
      id: "doc-4", title: "Mount Templates",
      tags: ["mounts", "configuration"],
      updatedAt: Date().addingTimeInterval(-345_600),
      markdownContent: """
      # Mount Templates

      Mount templates define how sessions get access to filesystem directories.

      ## Template Types

      ### `folder`
      Creates an isolated workspace copy from a template directory for each session.

      ## Configuration

      Mount templates are managed via the API:

      ```json
      {
        "name": "wuhu-swift",
        "type": "folder",
        "templatePath": "/path/to/template",
        "workspacesPath": "/path/to/workspaces"
      }
      ```

      ## Usage

      When creating a session, specify a mount template:

      ```json
      {
        "provider": "anthropic",
        "model": "claude-sonnet-4-6",
        "mountTemplate": "wuhu-swift"
      }
      ```

      The server will create a workspace copy and bind it to the session.
      """,
    ),
  ]

}
