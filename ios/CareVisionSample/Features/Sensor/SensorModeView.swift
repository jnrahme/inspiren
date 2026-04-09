import AVFoundation
import SwiftUI

struct SensorModeView: View {
  @StateObject private var viewModel: SensorModeViewModel

  init(settings: DemoSettings) {
    _viewModel = StateObject(wrappedValue: SensorModeViewModel(settings: settings))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      SensorHeaderCard(viewModel: viewModel)
      SensorStreamingCard(viewModel: viewModel, streamManager: viewModel.streamManager)
      SensorCameraCard(
        cameraState: viewModel.cameraState,
        zone: viewModel.zone,
        session: viewModel.cameraSession
      )
      SensorDetectionCard(detection: viewModel.detection)
      SensorCalibrationCard(
        zone: zoneBinding(\.x),
        zoneY: zoneBinding(\.y),
        zoneWidth: zoneBinding(\.width),
        zoneHeight: zoneBinding(\.height)
      )
    }
    .task {
      await viewModel.startIfNeeded()
    }
    .onDisappear {
      viewModel.stop()
    }
  }

  private func zoneBinding(_ keyPath: WritableKeyPath<ZoneConfiguration, Double>) -> Binding<Double> {
    Binding {
      viewModel.zone[keyPath: keyPath]
    } set: { newValue in
      var updated = viewModel.zone
      updated[keyPath: keyPath] = newValue
      viewModel.updateZone(updated)
    }
  }
}

private struct SensorHeaderCard: View {
  @ObservedObject var viewModel: SensorModeViewModel

  var body: some View {
    PanelCard {
      Text("Sensor Mode")
        .font(.system(.title2, design: .rounded).weight(.heavy))
      Text("Capture the room, estimate posture, and detect when someone is sitting up, standing, or leaving the bedside zone.")
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.secondary)

      HStack(spacing: 10) {
        StatusBadge(title: "Camera", value: viewModel.cameraState.label)
        StatusBadge(
          title: "Publisher",
          value: viewModel.streamManager.isPublishing ? "Live" : "Idle",
          tint: viewModel.streamManager.isPublishing ? AppTheme.success.opacity(0.14) : Color.white.opacity(0.68),
          foreground: viewModel.streamManager.isPublishing ? AppTheme.success : AppTheme.accent
        )
      }

      Text(viewModel.streamSummary)
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(.secondary)
      Text(viewModel.eventSummary)
        .font(.system(.footnote, design: .rounded))
        .foregroundStyle(.secondary)

      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .font(.system(.footnote, design: .rounded))
          .foregroundStyle(AppTheme.alert)
      }

      HStack {
        Button("Reconnect") {
          Task {
            await viewModel.reconnect()
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)

        Button("Trigger Demo Alert") {
          Task {
            await viewModel.triggerManualEvent()
          }
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

private struct SensorStreamingCard: View {
  @ObservedObject var viewModel: SensorModeViewModel
  @ObservedObject var streamManager: LiveKitRoomManager

  var body: some View {
    PanelCard {
      Text("Live Stream Publisher")
        .font(.system(.headline, design: .rounded).weight(.bold))
      Text("This publishes the same camera frames that drive the on-device Vision loop, so the caregiver device can watch the room without switching Sensor Mode into a separate capture path.")
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
          value: streamManager.isPublishing ? "Publishing" : "Not live",
          tint: streamManager.isPublishing ? AppTheme.success.opacity(0.14) : Color.white.opacity(0.68),
          foreground: streamManager.isPublishing ? AppTheme.success : AppTheme.accent
        )
        StatusBadge(
          title: "Overlay",
          value: viewModel.overlay.isRenderable ? "Active" : "Idle",
          tint: viewModel.overlay.isRenderable ? AppTheme.success.opacity(0.14) : Color.white.opacity(0.68),
          foreground: viewModel.overlay.isRenderable ? AppTheme.success : AppTheme.accent
        )
      }

      Group {
        if let track = streamManager.localVideoTrack {
          ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .fill(Color.black.opacity(0.88))

            LiveVideoTrackView(track: track)
            MotionOverlayView(overlay: viewModel.overlay)
          }
          .frame(height: 220)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else {
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(AppTheme.hero.opacity(0.9))
            .frame(height: 220)
            .overlay(alignment: .bottomLeading) {
              Text("Local live preview appears here after the room connects and the camera publish succeeds.")
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

      HStack {
        Button("Start Live Stream") {
          Task {
            await viewModel.startStreaming()
          }
        }
        .buttonStyle(.borderedProminent)
        .tint(AppTheme.accent)

        Button("Stop Live Stream") {
          Task {
            await viewModel.stopStreaming()
          }
        }
        .buttonStyle(.bordered)
        .disabled(!streamManager.isConnected)
      }
    }
  }
}

private struct SensorCameraCard: View {
  let cameraState: CameraRuntimeState
  let zone: ZoneConfiguration
  let session: AVCaptureSession

  var body: some View {
    PanelCard {
      Text("Camera + Bedside Zone")
        .font(.system(.headline, design: .rounded).weight(.bold))

      ZStack(alignment: .topLeading) {
        cameraSurface
          .frame(height: 320)
          .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

        ZoneOverlay(zone: zone)
          .allowsHitTesting(false)
          .frame(height: 320)
      }
    }
  }

  private var cameraSurface: AnyView {
    switch cameraState {
    case .live, .starting:
      return AnyView(CameraPreviewView(session: session))

    case .fallback, .failed, .idle:
      return AnyView(
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                AppTheme.accent.opacity(0.25),
                Color(red: 0.13, green: 0.24, blue: 0.33).opacity(0.78),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )
          .overlay(alignment: .bottomLeading) {
            Text(cameraState.detail)
              .font(.system(.subheadline, design: .rounded).weight(.medium))
              .foregroundStyle(.white.opacity(0.9))
              .padding(20)
          }
      )
    }
  }
}

private struct SensorDetectionCard: View {
  let detection: DetectionSnapshot

  var body: some View {
    PanelCard {
      Text("Detection Readout")
        .font(.system(.headline, design: .rounded).weight(.bold))

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        MetricTile(
          title: "Person",
          value: detection.personDetected ? "Detected" : "Not seen",
          tint: detection.personDetected ? AppTheme.success : .secondary
        )
        MetricTile(
          title: "Bedside Zone",
          value: detection.zoneOccupied ? "Occupied" : "Clear",
          tint: detection.zoneOccupied ? AppTheme.alert : .secondary
        )
        MetricTile(
          title: "Activity",
          value: detection.activityLabel.title,
          tint: detection.activityLabel == .clear ? .secondary : AppTheme.alert
        )
        MetricTile(
          title: "Motion",
          value: String(format: "%.2f", detection.motionScore),
          tint: AppTheme.accent
        )
        MetricTile(
          title: "Pose",
          value: detection.poseLabel.title,
          tint: detection.poseLabel == .standing ? AppTheme.success : AppTheme.accent
        )
        MetricTile(
          title: "Upright",
          value: String(format: "%.2f", detection.uprightScore),
          tint: detection.uprightScore >= 0.68 ? AppTheme.success : AppTheme.accent
        )
        MetricTile(
          title: "Legs",
          value: String(format: "%.2f", detection.legExtensionScore),
          tint: AppTheme.accent
        )
        MetricTile(
          title: "Confidence",
          value: String(format: "%.2f", detection.confidence),
          tint: AppTheme.accent
        )
      }
    }
  }
}

private struct SensorCalibrationCard: View {
  let zone: Binding<Double>
  let zoneY: Binding<Double>
  let zoneWidth: Binding<Double>
  let zoneHeight: Binding<Double>

  var body: some View {
    PanelCard {
      Text("Quick Calibration")
        .font(.system(.headline, design: .rounded).weight(.bold))
      Text("The red overlay is the monitored bedside zone. The detector looks for `in bed -> sitting up -> standing -> leaving zone` over time.")
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.secondary)

      ZoneSliderRow(title: "X Position", value: zone, range: 0 ... 0.9)
      ZoneSliderRow(title: "Y Position", value: zoneY, range: 0 ... 0.9)
      ZoneSliderRow(title: "Width", value: zoneWidth, range: 0.1 ... 0.5)
      ZoneSliderRow(title: "Height", value: zoneHeight, range: 0.1 ... 0.8)
    }
  }
}

private struct ZoneSliderRow: View {
  let title: String
  let value: Binding<Double>
  let range: ClosedRange<Double>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(title)
          .font(.system(.caption, design: .rounded).weight(.semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
          .font(.system(.caption, design: .rounded).weight(.bold))
          .foregroundStyle(AppTheme.accent)
      }
      Slider(value: value, in: range)
        .tint(AppTheme.accent)
    }
  }
}

private struct ZoneOverlay: View {
  let zone: ZoneConfiguration

  var body: some View {
    GeometryReader { proxy in
      let width = proxy.size.width * zone.width
      let height = proxy.size.height * zone.height
      let originX = proxy.size.width * zone.x
      let originY = proxy.size.height * zone.y

      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(AppTheme.alert, style: StrokeStyle(lineWidth: 3, dash: [10, 8]))
        .background(
          RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(AppTheme.alert.opacity(0.14))
        )
        .frame(width: width, height: height)
        .position(x: originX + width / 2, y: originY + height / 2)
    }
  }
}
