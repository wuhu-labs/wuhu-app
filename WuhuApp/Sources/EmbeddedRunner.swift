#if os(macOS)

import Foundation
import Logging
import WuhuCore

/// Manages an embedded Wuhu runner that connects out to a Wuhu server.
///
/// When enabled, the app acts as both a UI client AND a runner: it connects
/// to the server's `/v1/runners/ws` WebSocket endpoint, advertises itself
/// with a configurable runner name, and executes bash/file operations locally.
///
/// Settings are persisted in UserDefaults.
@Observable
@MainActor
final class EmbeddedRunner {
  enum Status: Equatable, Sendable {
    case disabled
    case connecting
    case connected
    case disconnected(String)
  }

  /// Whether the embedded runner is enabled.
  var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
      if isEnabled {
        startIfNeeded()
      } else {
        stop()
      }
    }
  }

  /// Runner name advertised in the hello handshake.
  var runnerName: String {
    didSet {
      UserDefaults.standard.set(runnerName, forKey: Self.runnerNameKey)
      restartIfRunning()
    }
  }

  /// Current connection status.
  private(set) var status: Status = .disabled

  /// Internal setter for use by StatusSetter bridge.
  fileprivate func setStatus(_ newStatus: Status) {
    status = newStatus
  }

  private var connectionTask: Task<Void, Never>?

  // MARK: - Persistence keys

  private static let enabledKey = "wuhuEmbeddedRunnerEnabled"
  private static let runnerNameKey = "wuhuEmbeddedRunnerName"

  // MARK: - Init

  init() {
    isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    runnerName = UserDefaults.standard.string(forKey: Self.runnerNameKey)
      ?? Host.current().localizedName
      ?? ProcessInfo.processInfo.hostName
  }

  // MARK: - Lifecycle

  func startIfNeeded() {
    guard isEnabled else {
      status = .disabled
      return
    }
    guard connectionTask == nil else { return }

    let name = runnerName
    let serverURL = sharedBaseURL.url.absoluteString

    status = .connecting

    // Use a sendable status setter to avoid capturing self across isolation boundaries.
    let setStatus = StatusSetter(runner: self)

    connectionTask = Task.detached {
      let runner = LocalRunner()
      var logger = Logger(label: "EmbeddedRunner")
      logger.logLevel = .info

      let config = RunnerOutboundClient.Config(
        runnerName: name,
        serverURL: serverURL,
        logger: logger,
        onConnected: {
          Task { @MainActor in setStatus.set(.connected) }
        },
        onDisconnected: {
          Task { @MainActor in setStatus.set(.disconnected("Disconnected")) }
        },
      )

      // Reconnect loop — runs forever until cancelled
      var backoff: UInt64 = 1_000_000_000
      let maxBackoff: UInt64 = 30_000_000_000

      while !Task.isCancelled {
        await setStatus.setAsync(.connecting)

        let connected = await RunnerOutboundClient.connect(config: config, runner: runner)

        if connected {
          backoff = 1_000_000_000
        }

        if Task.isCancelled { break }

        await setStatus.setAsync(.disconnected("Reconnecting…"))

        try? await Task.sleep(nanoseconds: backoff)
        backoff = min(backoff * 2, maxBackoff)
      }

      await setStatus.setAsync(.disabled)
    }
  }

  func stop() {
    connectionTask?.cancel()
    connectionTask = nil
    status = isEnabled ? .disconnected("Stopped") : .disabled
  }

  private func restartIfRunning() {
    guard connectionTask != nil else { return }
    stop()
    startIfNeeded()
  }
}

// MARK: - StatusSetter (Sendable bridge)

/// A sendable wrapper that allows a detached task to set status
/// on the MainActor-isolated EmbeddedRunner without capturing it directly.
private struct StatusSetter: @unchecked Sendable {
  weak var runner: EmbeddedRunner?

  @MainActor
  func set(_ status: EmbeddedRunner.Status) {
    runner?.setStatus(status)
  }

  func setAsync(_ status: EmbeddedRunner.Status) async {
    await MainActor.run { set(status) }
  }
}

#endif
