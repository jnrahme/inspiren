import SwiftUI

struct RolePickerView: View {
  @Binding var selectedMode: AppMode

  var body: some View {
    PanelCard {
      Text("Select the role you want to demo.")
        .font(.system(.headline, design: .rounded).weight(.bold))

      Picker("Role", selection: $selectedMode) {
        ForEach(AppMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)

      Text(selectedMode.subtitle)
        .font(.system(.subheadline, design: .rounded))
        .foregroundStyle(.secondary)
    }
  }
}
