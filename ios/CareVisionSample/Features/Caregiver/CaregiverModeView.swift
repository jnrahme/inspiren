import SwiftUI

struct CaregiverModeView: View {
  @StateObject private var viewModel: CaregiverModeViewModel

  init(settings: DemoSettings) {
    _viewModel = StateObject(wrappedValue: CaregiverModeViewModel(settings: settings))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      CaregiverStreamingCard(
        streamManager: viewModel.streamManager,
        fallbackOverlay: viewModel.overlay
      )

      PanelCard {
        Text("Caregiver Mode")
          .font(.system(.title2, design: .rounded).weight(.heavy))
        Text("Watch the realtime alert channel, inspect the timeline, and acknowledge high-priority events.")
          .font(.system(.subheadline, design: .rounded))
          .foregroundStyle(.secondary)

        HStack(spacing: 10) {
          StatusBadge(title: "Realtime", value: viewModel.connectionSummary)
          StatusBadge(title: "Alerts", value: "\(viewModel.alerts.count)")
        }

        Text(viewModel.streamSummary)
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(.secondary)

        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(AppTheme.alert)
        }

        Button("Reconnect Feed") {
          Task {
            await viewModel.reconnect()
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)
      }

      PanelCard {
        Text("Alert Inbox")
          .font(.system(.headline, design: .rounded).weight(.bold))

        if viewModel.alerts.isEmpty {
          Text("No alerts yet. Trigger one from Sensor Mode and it should land here in realtime.")
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
        } else {
          VStack(spacing: 12) {
            ForEach(viewModel.alerts) { alert in
              alertCard(alert)
            }
          }
        }
      }

      PanelCard {
        Text("Room Timeline")
          .font(.system(.headline, design: .rounded).weight(.bold))

        if viewModel.timeline.isEmpty {
          Text("Timeline is empty for this room.")
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
        } else {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.timeline) { entry in
              VStack(alignment: .leading, spacing: 4) {
                Text(entry.summary)
                  .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Text(entry.createdAt)
                  .font(.system(.caption, design: .rounded))
                  .foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(14)
              .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                  .fill(Color.white.opacity(0.62))
              )
            }
          }
        }
      }
    }
    .task {
      await viewModel.startIfNeeded()
    }
    .onDisappear {
      viewModel.stop()
    }
  }

  private func alertCard(_ alert: AlertItem) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 4) {
          Text(alert.title)
            .font(.system(.headline, design: .rounded).weight(.bold))
          Text(alert.body)
            .font(.system(.subheadline, design: .rounded))
            .foregroundStyle(.secondary)
        }

        Spacer()

        StatusBadge(
          title: alert.priority.rawValue,
          value: alert.state.rawValue,
          tint: (alert.priority == .high ? AppTheme.alert : AppTheme.accent).opacity(0.14),
          foreground: alert.priority == .high ? AppTheme.alert : AppTheme.accent
        )
      }

      HStack {
        Text(alert.createdAt)
          .font(.system(.caption, design: .rounded))
          .foregroundStyle(.secondary)
        Spacer()
        if alert.state == .new {
          Button("Acknowledge") {
            Task {
              await viewModel.acknowledge(alert)
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(AppTheme.success)
        }
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 22, style: .continuous)
        .fill(Color.white.opacity(0.62))
    )
  }
}

private struct CaregiverStreamingCard: View {
  @ObservedObject var streamManager: LiveKitRoomManager
  let fallbackOverlay: MotionOverlayFrame

  var body: some View {
    let overlay = resolvedOverlay()

    PanelCard {
      Text("Live Room View")
        .font(.system(.headline, design: .rounded).weight(.bold))
      Text("This subscribes to the room stream so the caregiver device can inspect the alert context without leaving the app.")
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        StatusBadge(
          title: "Stream",
          value: streamManager.isConnected ? "Connected" : "Idle",
          tint: streamManager.isConnected ? AppTheme.success.opacity(0.14) : Color.white.opacity(0.68),
          foreground: streamManager.isConnected ? AppTheme.success : AppTheme.accent
        )
        StatusBadge(
          title: "Video",
          value: streamManager.remoteVideoTrack == nil ? "Waiting" : "Receiving",
          tint: streamManager.remoteVideoTrack == nil ? Color.white.opacity(0.68) : AppTheme.success.opacity(0.14),
          foreground: streamManager.remoteVideoTrack == nil ? AppTheme.accent : AppTheme.success
        )
        StatusBadge(
          title: "Overlay",
          value: overlay.isRenderable ? "Tracked" : "Idle",
          tint: overlay.isRenderable ? AppTheme.success.opacity(0.14) : Color.white.opacity(0.68),
          foreground: overlay.isRenderable ? AppTheme.success : AppTheme.accent
        )
      }

      Group {
        if let track = streamManager.remoteVideoTrack {
          ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .fill(Color.black.opacity(0.88))

            LiveVideoTrackView(track: track)
            MotionOverlayView(overlay: overlay)
          }
          .frame(height: 240)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(AppTheme.hero.opacity(0.9))
            .frame(height: 240)
            .overlay(alignment: .bottomLeading) {
              Text("Waiting for a sensor device to publish video into this room.")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .padding(18)
            }
        }
      }

      Text(streamManager.connectionSummary)
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(.secondary)

      if let errorMessage = streamManager.errorMessage {
        Text(errorMessage)
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(AppTheme.alert)
      }
    }
  }

  private func resolvedOverlay() -> MotionOverlayFrame {
    let liveOverlay = streamManager.overlay

    if fallbackOverlay.updatedAt.isEmpty {
      return liveOverlay
    }

    if liveOverlay.updatedAt.isEmpty {
      return fallbackOverlay
    }

    return liveOverlay.updatedAt >= fallbackOverlay.updatedAt ? liveOverlay : fallbackOverlay
  }
}
