import ComposableArchitecture
import SwiftUI

// MARK: - Session List (content column)

struct SessionListView: View {
  @Bindable var store: StoreOf<SessionFeature>
  var onCreateSession: (() -> Void)?

  private var visibleSessions: IdentifiedArrayOf<MockSession> {
    if store.showArchived {
      store.sessions.filter { $0.parentSessionID == nil }
    } else {
      store.sessions.filter { !$0.isArchived && $0.parentSessionID == nil }
    }
  }

  var body: some View {
    List(selection: $store.selectedSessionID.sending(\.sessionSelected)) {
      ForEach(visibleSessions) { session in
        SessionRow(session: session)
          .tag(session.id)
          .contextMenu {
            Button("Rename…") {
              store.send(.renameMenuTapped(session.id))
            }
            Divider()
            if session.isArchived {
              Button("Unarchive") {
                store.send(.unarchiveSession(session.id))
              }
            } else {
              Button("Archive") {
                store.send(.archiveSession(session.id))
              }
            }
          }
      }
    }
    #if os(macOS)
    .listStyle(.sidebar)
    #else
    .listStyle(.inset)
    .navigationTitle("Sessions")
    #endif
    #if os(iOS)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Toggle(isOn: Binding(
          get: { store.showArchived },
          set: { _ in store.send(.toggleShowArchived) },
        )) {
          Label("Show Archived", systemImage: "archivebox")
        }
        .help("Show archived sessions")
      }
      if let onCreateSession {
        ToolbarItem(placement: .primaryAction) {
          Button {
            onCreateSession()
          } label: {
            Image(systemName: "plus")
          }
          .help("New Session")
        }
      }
    }
    #endif
    .alert("Rename Session", isPresented: $store.isShowingRenameDialog) {
      TextField("Session title", text: $store.renameText)
      Button("Rename") {
        store.send(.renameConfirmed)
      }
      Button("Cancel", role: .cancel) {
        store.send(.renameCancelled)
      }
    } message: {
      Text("Enter a new title for this session.")
    }
  }
}

// MARK: - Session Row

struct SessionRow: View {
  let session: MockSession

  var body: some View {
    HStack(spacing: 8) {
      Circle()
        .fill(statusColor)
        .frame(width: 8, height: 8)
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(session.title)
            .font(.callout)
            .fontWeight(.semibold)
            .lineLimit(1)
          if session.isArchived {
            Image(systemName: "archivebox")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Text(session.updatedAt, style: .relative)
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Text(session.lastMessagePreview)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 4)
    .opacity(session.isArchived ? 0.6 : 1.0)
  }

  private var statusColor: Color {
    switch session.status {
    case .running: .green
    case .idle: .gray
    case .stopped: .red
    }
  }
}
