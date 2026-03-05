import ComposableArchitecture
import Foundation
import IdentifiedCollections

// MARK: - Mock Message Channel

struct MockChannel: Identifiable, Equatable {
  let id: String
  var name: String
  var avatarEmoji: String
  var isGroup: Bool
  var lastMessage: String
  var lastMessageTime: Date
  var unreadCount: Int
  var members: [String]
}

// MARK: - Messages Feature

@Reducer
struct MessagesFeature {
  @ObservableState
  struct State {
    var channels: IdentifiedArrayOf<MockChannel> = IdentifiedArray(uniqueElements: MockChannelData.channels)
    var selectedChannelID: String?

    var selectedChannel: MockChannel? {
      guard let id = selectedChannelID else { return nil }
      return channels[id: id]
    }
  }

  enum Action {
    case channelSelected(String?)
  }

  var body: some ReducerOf<Self> {
    Reduce { state, action in
      switch action {
      case let .channelSelected(id):
        state.selectedChannelID = id
        return .none
      }
    }
  }
}

// MARK: - Mock Channel Data

enum MockChannelData {
  static let channels: [MockChannel] = [
    MockChannel(
      id: "ch-001",
      name: "Wuhu Core Team",
      avatarEmoji: "🚀",
      isGroup: true,
      lastMessage: "Let's ship the tri-panel layout this week",
      lastMessageTime: Date().addingTimeInterval(-300),
      unreadCount: 3,
      members: ["minsheng", "anna", "kesou", "yihan"]
    ),
    MockChannel(
      id: "ch-002",
      name: "Anna Chen",
      avatarEmoji: "👩‍💻",
      isGroup: false,
      lastMessage: "The WebSocket reconnection PR is ready for review",
      lastMessageTime: Date().addingTimeInterval(-1800),
      unreadCount: 1,
      members: ["anna"]
    ),
    MockChannel(
      id: "ch-003",
      name: "Design Review",
      avatarEmoji: "🎨",
      isGroup: true,
      lastMessage: "I like the Arc-style floating panels approach",
      lastMessageTime: Date().addingTimeInterval(-3600),
      unreadCount: 0,
      members: ["minsheng", "anna", "yihan"]
    ),
    MockChannel(
      id: "ch-004",
      name: "Kesou Wang",
      avatarEmoji: "🔧",
      isGroup: false,
      lastMessage: "CI is green again after the Swift 6.2 update",
      lastMessageTime: Date().addingTimeInterval(-7200),
      unreadCount: 0,
      members: ["kesou"]
    ),
    MockChannel(
      id: "ch-005",
      name: "Infrastructure",
      avatarEmoji: "🏗️",
      isGroup: true,
      lastMessage: "We need to add rate limiting before the public launch",
      lastMessageTime: Date().addingTimeInterval(-14400),
      unreadCount: 5,
      members: ["minsheng", "kesou", "yihan"]
    ),
    MockChannel(
      id: "ch-006",
      name: "Yihan Li",
      avatarEmoji: "📊",
      isGroup: false,
      lastMessage: "Database migration is complete, all 12k rows intact",
      lastMessageTime: Date().addingTimeInterval(-28800),
      unreadCount: 0,
      members: ["yihan"]
    ),
    MockChannel(
      id: "ch-007",
      name: "Random",
      avatarEmoji: "🎲",
      isGroup: true,
      lastMessage: "Has anyone tried the new ramen place on 3rd?",
      lastMessageTime: Date().addingTimeInterval(-43200),
      unreadCount: 12,
      members: ["minsheng", "anna", "kesou", "yihan"]
    ),
    MockChannel(
      id: "ch-008",
      name: "Release Notes",
      avatarEmoji: "📝",
      isGroup: true,
      lastMessage: "v1.0.1-31 shipped to TestFlight",
      lastMessageTime: Date().addingTimeInterval(-86400),
      unreadCount: 0,
      members: ["minsheng", "anna"]
    ),
  ]
}
