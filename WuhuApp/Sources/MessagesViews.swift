import ComposableArchitecture
import SwiftUI

// MARK: - Messages List Panel View

#if os(macOS)
  struct MessagesListPanelView: View {
    @Bindable var store: StoreOf<MessagesFeature>

    var body: some View {
      List(selection: $store.selectedChannelID.sending(\.channelSelected)) {
        ForEach(store.channels) { channel in
          ChannelRow(channel: channel)
            .tag(channel.id)
        }
      }
      .listStyle(.sidebar)
    }
  }

  // MARK: - Channel Row

  struct ChannelRow: View {
    let channel: MockChannel

    var body: some View {
      HStack(spacing: 10) {
        // Avatar
        Text(channel.avatarEmoji)
          .font(.title3)
          .frame(width: 32, height: 32)
          .background(Color.gray.opacity(0.1))
          .clipShape(Circle())

        VStack(alignment: .leading, spacing: 2) {
          HStack {
            Text(channel.name)
              .font(.system(size: 13, weight: .medium))
              .lineLimit(1)
            Spacer()
            Text(channel.lastMessageTime, style: .relative)
              .font(.caption2)
              .foregroundStyle(.tertiary)
          }
          Text(channel.lastMessage)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }

        if channel.unreadCount > 0 {
          Text("\(channel.unreadCount)")
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.orange)
            .foregroundStyle(.white)
            .clipShape(Capsule())
        }
      }
      .padding(.vertical, 4)
    }
  }
#endif
