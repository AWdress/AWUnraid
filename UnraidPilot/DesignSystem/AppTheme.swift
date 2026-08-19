import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.025, green: 0.055, blue: 0.09)
    static let surface = Color(red: 0.055, green: 0.095, blue: 0.14)
    static let surfaceRaised = Color(red: 0.075, green: 0.12, blue: 0.17)
    static let divider = Color.white.opacity(0.09)
    static let secondaryText = Color(red: 0.58, green: 0.64, blue: 0.71)
    static let accent = Color(red: 0.05, green: 0.68, blue: 0.98)
    static let healthy = Color(red: 0.18, green: 0.82, blue: 0.39)
    static let warning = Color(red: 1.0, green: 0.59, blue: 0.08)
}

struct SurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.06)))
    }
}

extension View {
    func appSurface() -> some View { modifier(SurfaceModifier()) }
}
