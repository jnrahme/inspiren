import SwiftUI

enum AppTheme {
  static let canvas = LinearGradient(
    colors: [
      Color(red: 0.95, green: 0.97, blue: 1.0),
      Color(red: 0.88, green: 0.94, blue: 0.93),
      Color(red: 0.99, green: 0.95, blue: 0.9),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let hero = LinearGradient(
    colors: [
      Color(red: 0.13, green: 0.24, blue: 0.33),
      Color(red: 0.08, green: 0.43, blue: 0.47),
    ],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  static let accent = Color(red: 0.08, green: 0.48, blue: 0.52)
  static let alert = Color(red: 0.82, green: 0.29, blue: 0.18)
  static let success = Color(red: 0.22, green: 0.58, blue: 0.39)
  static let cardFill = Color.white.opacity(0.72)
  static let cardStroke = Color.white.opacity(0.68)
  static let shadow = Color.black.opacity(0.08)
}
