import SwiftUI

struct AppRootView: View {
  #if targetEnvironment(simulator)
    private static let defaultSelectedMode: AppMode = .caregiver
  #else
    private static let defaultSelectedMode: AppMode = .sensor
  #endif

  @AppStorage("carevision.baseURL") private var baseURLString = "http://127.0.0.1:8787"
  @AppStorage("carevision.roomId") private var roomId = "room-demo-a"
  @AppStorage("carevision.sensorName") private var sensorDisplayName = "Sensor iPhone"
  @AppStorage("carevision.caregiverName") private var caregiverDisplayName = "Caregiver iPhone"
  @AppStorage("carevision.deviceId") private var sensorDeviceId = "sensor-device-01"
  @AppStorage("carevision.selectedMode") private var selectedModeRawValue = AppRootView.defaultSelectedMode.rawValue
  @AppStorage("carevision.zone.x") private var zoneX = ZoneConfiguration.defaultBedside.x
  @AppStorage("carevision.zone.y") private var zoneY = ZoneConfiguration.defaultBedside.y
  @AppStorage("carevision.zone.width") private var zoneWidth = ZoneConfiguration.defaultBedside.width
  @AppStorage("carevision.zone.height") private var zoneHeight = ZoneConfiguration.defaultBedside.height

  @State private var isPresentingSettings = false

  private var selectedMode: AppMode {
    AppMode(rawValue: selectedModeRawValue) ?? Self.defaultSelectedMode
  }

  private var selectedModeBinding: Binding<AppMode> {
    Binding(
      get: { selectedMode },
      set: { selectedModeRawValue = $0.rawValue }
    )
  }

  private var settings: DemoSettings {
    DemoSettings(
      baseURLString: baseURLString,
      roomId: roomId,
      sensorDisplayName: sensorDisplayName,
      caregiverDisplayName: caregiverDisplayName,
      sensorDeviceId: sensorDeviceId,
      zone: ZoneConfiguration(
        x: zoneX,
        y: zoneY,
        width: zoneWidth,
        height: zoneHeight
      ).clamped
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        AppTheme.canvas
          .ignoresSafeArea()

        ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            RolePickerView(selectedMode: selectedModeBinding)

            if selectedMode == .sensor {
              SensorModeView(settings: settings)
                .id("sensor-\(settings.signature)")
            } else {
              CaregiverModeView(settings: settings)
                .id("caregiver-\(settings.signature)")
            }

            heroCard
          }
          .padding(20)
        }
      }
      .navigationTitle("Care Vision Sample")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Setup") {
            isPresentingSettings = true
          }
        }
      }
      .sheet(isPresented: $isPresentingSettings) {
        NavigationStack {
          Form {
            Section("Backend") {
              TextField("Base URL", text: $baseURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
              TextField("Room ID", text: $roomId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section("Display Names") {
              TextField("Sensor name", text: $sensorDisplayName)
              TextField("Caregiver name", text: $caregiverDisplayName)
              TextField("Sensor device ID", text: $sensorDeviceId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            Section("Default Exit Zone") {
              LabeledContent("X", value: zoneX.formatted(.number.precision(.fractionLength(2))))
              Slider(value: $zoneX, in: 0 ... 0.9)

              LabeledContent("Y", value: zoneY.formatted(.number.precision(.fractionLength(2))))
              Slider(value: $zoneY, in: 0 ... 0.9)

              LabeledContent("Width", value: zoneWidth.formatted(.number.precision(.fractionLength(2))))
              Slider(value: $zoneWidth, in: 0.1 ... 0.5)

              LabeledContent("Height", value: zoneHeight.formatted(.number.precision(.fractionLength(2))))
              Slider(value: $zoneHeight, in: 0.1 ... 0.8)
            }
          }
          .navigationTitle("Demo Setup")
          .navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Button("Done") {
                let clamped = ZoneConfiguration(
                  x: zoneX,
                  y: zoneY,
                  width: zoneWidth,
                  height: zoneHeight
                ).clamped
                zoneX = clamped.x
                zoneY = clamped.y
                zoneWidth = clamped.width
                zoneHeight = clamped.height
                isPresentingSettings = false
              }
            }
          }
        }
        .presentationDetents([.large])
      }
    }
  }

  private var heroCard: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 30, style: .continuous)
        .fill(AppTheme.hero)
        .shadow(color: AppTheme.shadow, radius: 20, x: 0, y: 12)

      VStack(alignment: .leading, spacing: 14) {
        Text("Ambient care response MVP")
          .font(.system(.headline, design: .rounded).weight(.semibold))
          .foregroundStyle(.white.opacity(0.75))
          .textCase(.uppercase)

        Text("One app, two roles, real backend wiring.")
          .font(.system(size: 30, weight: .heavy, design: .rounded))
          .foregroundStyle(.white)

        Text("Sensor Mode handles room-side camera + Vision heuristics. Caregiver Mode handles alert intake, acknowledgement, and timeline updates.")
          .font(.system(.body, design: .rounded))
          .foregroundStyle(.white.opacity(0.86))

        HStack(spacing: 10) {
          StatusBadge(title: "Backend", value: baseURLString, tint: .white.opacity(0.16), foreground: .white)
          StatusBadge(title: "Room", value: roomId, tint: .white.opacity(0.16), foreground: .white)
        }
      }
      .padding(24)
    }
    .frame(minHeight: 210)
  }
}
