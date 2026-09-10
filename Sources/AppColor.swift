import SwiftUI

/// MacPeel's identity color, from the design system's per-app accent table
/// (v2 "modern & colorful" refresh) — matches the new app icon's gradient
/// start. Used deliberately instead of `Color.accentColor` in most spots so
/// MacPeel keeps its own purple identity even when the user's system accent
/// color differs; `Color.accentColor` stays correct for a couple of "obviously
/// system" spots.
extension Color {
    static let appAccent = Color(red: 0.55, green: 0.30, blue: 0.90)
}
