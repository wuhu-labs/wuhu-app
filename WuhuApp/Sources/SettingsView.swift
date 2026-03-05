import SwiftUI

// MARK: - Settings

struct SettingsView: View {
  @AppStorage("wuhuUsername") private var username = ""
  @State private var workspaces: [Workspace]
  @State private var activeWorkspace: Workspace
  var onSwitchWorkspace: ((Workspace) -> Void)?

  #if os(macOS)
  var embeddedRunner: EmbeddedRunner?
  #endif

  @State private var isAddingWorkspace = false
  @State private var newWorkspaceName = ""
  @State private var newWorkspaceURL = "http://localhost:8080"

  @State private var editingWorkspace: Workspace?
  @State private var editName = ""
  @State private var editURL = ""

  #if os(macOS)
  init(
    workspaces: [Workspace],
    activeWorkspace: Workspace,
    onSwitchWorkspace: ((Workspace) -> Void)?,
    embeddedRunner: EmbeddedRunner? = nil,
  ) {
    _workspaces = State(initialValue: workspaces)
    _activeWorkspace = State(initialValue: activeWorkspace)
    self.onSwitchWorkspace = onSwitchWorkspace
    self.embeddedRunner = embeddedRunner
  }
  #else
  init(
    workspaces: [Workspace],
    activeWorkspace: Workspace,
    onSwitchWorkspace: ((Workspace) -> Void)?,
  ) {
    _workspaces = State(initialValue: workspaces)
    _activeWorkspace = State(initialValue: activeWorkspace)
    self.onSwitchWorkspace = onSwitchWorkspace
  }
  #endif

  var body: some View {
    Form {
      Section("Workspaces") {
        ForEach(workspaces, id: \.id) { workspace in
          HStack {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(workspace.name)
                  .fontWeight(workspace.id == activeWorkspace.id ? .semibold : .regular)
                if workspace.id == activeWorkspace.id {
                  Text("Active")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
                }
              }
              Text(workspace.serverURL)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if workspace.id != activeWorkspace.id {
              Button("Switch") {
                switchTo(workspace)
              }
              .buttonStyle(.borderless)
            }
            Button {
              editingWorkspace = workspace
              editName = workspace.name
              editURL = workspace.serverURL
            } label: {
              Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            if workspaces.count > 1 {
              Button(role: .destructive) {
                removeWorkspace(workspace)
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
            }
          }
          .padding(.vertical, 2)
        }

        Button {
          isAddingWorkspace = true
          newWorkspaceName = ""
          newWorkspaceURL = "http://localhost:8080"
        } label: {
          Label("Add Workspace", systemImage: "plus")
        }
      }

      #if os(macOS)
      if let embeddedRunner {
        RunnerSettingsSection(runner: embeddedRunner)
      }
      #endif

      Section("Identity") {
        TextField("Username", text: $username)
          .textFieldStyle(.roundedBorder)
        Text("Displayed as the author of your messages.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    #if os(macOS)
      .frame(width: 480)
    #endif
      .alert("Add Workspace", isPresented: $isAddingWorkspace) {
        TextField("Name", text: $newWorkspaceName)
        TextField("Server URL", text: $newWorkspaceURL)
        Button("Add") { addWorkspace() }
        Button("Cancel", role: .cancel) {}
      } message: {
        Text("Enter a name and server URL for the new workspace.")
      }
      .alert("Edit Workspace", isPresented: Binding(
        get: { editingWorkspace != nil },
        set: { if !$0 { editingWorkspace = nil } },
      )) {
        TextField("Name", text: $editName)
        TextField("Server URL", text: $editURL)
        Button("Save") { saveEditedWorkspace() }
        Button("Cancel", role: .cancel) { editingWorkspace = nil }
      } message: {
        Text("Update the workspace name and server URL.")
      }
  }

  private func addWorkspace() {
    let name = newWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = newWorkspaceURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !url.isEmpty else { return }
    let workspace = Workspace(name: name, serverURL: url)
    workspaces.append(workspace)
    WorkspaceStorage.saveWorkspaces(workspaces)
  }

  private func removeWorkspace(_ workspace: Workspace) {
    workspaces.removeAll { $0.id == workspace.id }
    WorkspaceStorage.saveWorkspaces(workspaces)
    // If we removed the active one, switch to the first available
    if workspace.id == activeWorkspace.id, let first = workspaces.first {
      switchTo(first)
    }
  }

  private func switchTo(_ workspace: Workspace) {
    activeWorkspace = workspace
    WorkspaceStorage.saveActiveWorkspaceID(workspace.id)
    onSwitchWorkspace?(workspace)
  }

  private func saveEditedWorkspace() {
    guard let editing = editingWorkspace else { return }
    let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
    let url = editURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !url.isEmpty else { return }

    if let index = workspaces.firstIndex(where: { $0.id == editing.id }) {
      workspaces[index].name = name
      workspaces[index].serverURL = url
      WorkspaceStorage.saveWorkspaces(workspaces)

      // If we edited the active workspace, update it and notify
      if editing.id == activeWorkspace.id {
        activeWorkspace = workspaces[index]
        // Update shared URL and notify reducer
        if let parsedURL = URL(string: url) {
          sharedBaseURL.update(parsedURL)
        }
        onSwitchWorkspace?(workspaces[index])
      }
    }
    editingWorkspace = nil
  }
}

// MARK: - Runner Settings

#if os(macOS)

struct RunnerSettingsSection: View {
  @Bindable var runner: EmbeddedRunner

  var body: some View {
    Section("Runner") {
      Toggle("Enable embedded runner", isOn: $runner.isEnabled)

      if runner.isEnabled {
        TextField("Runner Name", text: $runner.runnerName)
          .textFieldStyle(.roundedBorder)
        Text("The name this runner advertises to the Wuhu server. Agents see this in list_runners.")
          .font(.caption)
          .foregroundStyle(.secondary)

        HStack(spacing: 8) {
          statusIndicator
          statusText
        }
      }
    }
  }

  @ViewBuilder
  private var statusIndicator: some View {
    switch runner.status {
    case .disabled:
      Image(systemName: "circle")
        .foregroundStyle(.secondary)
    case .connecting:
      ProgressView()
        .controlSize(.small)
    case .connected:
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
    case .disconnected:
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    }
  }

  @ViewBuilder
  private var statusText: some View {
    switch runner.status {
    case .disabled:
      Text("Disabled")
        .foregroundStyle(.secondary)
    case .connecting:
      Text("Connecting to server…")
        .foregroundStyle(.secondary)
    case .connected:
      Text("Connected")
        .foregroundStyle(.green)
    case let .disconnected(reason):
      Text(reason)
        .foregroundStyle(.orange)
    }
  }
}

#endif
