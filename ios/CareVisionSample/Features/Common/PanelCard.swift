import SwiftUI

struct PanelCard<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      content
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .fill(AppTheme.cardFill)
        .overlay(
          RoundedRectangle(cornerRadius: 28, style: .continuous)
            .stroke(AppTheme.cardStroke, lineWidth: 1)
        )
    )
    .shadow(color: AppTheme.shadow, radius: 16, x: 0, y: 10)
  }
}

struct StatusBadge: View {
  let title: String
  let value: String
  var tint: Color = AppTheme.accent.opacity(0.12)
  var foreground: Color = AppTheme.accent

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title.uppercased())
        .font(.system(.caption2, design: .rounded).weight(.bold))
        .foregroundStyle(foreground.opacity(0.72))
      Text(value)
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(foreground)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(tint)
    )
  }
}

struct MetricTile: View {
  let title: String
  let value: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(.caption, design: .rounded).weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.system(.headline, design: .rounded).weight(.bold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(14)
    .background(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .fill(Color.white.opacity(0.62))
    )
  }
}
