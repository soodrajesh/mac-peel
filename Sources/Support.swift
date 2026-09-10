import AppKit
import SwiftUI

/// The app's Text Size setting, plus a per-view `.appFont(_:weight:)`
/// modifier — deliberately *not* SwiftUI's `.dynamicTypeSize`/
/// `Font.TextStyle`, because Dynamic Type is an iOS/iPadOS/tvOS/watchOS
/// mechanism with no effect on macOS. This mirrors MacGroom's own
/// `Support.swift` (`mac-cleanup/Sources/Support.swift`): a scale factor
/// read from the environment, applied to a fixed base point size per
/// semantic role, computed fresh at render time so a Settings change
/// applies live.
private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

/// One semantic role → one base point size, matching macOS's own
/// approximate `NSFont.preferredFont(forTextStyle:)` values.
enum AppFontStyle {
    case largeTitle, title, title2, title3
    case headline, body, callout, subheadline, footnote, caption, caption2

    var basePointSize: CGFloat {
        switch self {
        case .largeTitle:  return 26
        case .title:       return 22
        case .title2:      return 17
        case .title3:      return 15
        case .headline:    return 13
        case .body:        return 13
        case .callout:     return 12
        case .subheadline: return 11
        case .footnote:    return 10
        case .caption:     return 10
        case .caption2:    return 10
        }
    }

    /// SwiftUI's real `.headline` renders semibold, not regular — every
    /// other style here defaults to regular.
    var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.textScale) private var scale
    let style: AppFontStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(.system(size: style.basePointSize * scale, weight: weight ?? style.defaultWeight))
    }
}

extension View {
    /// Replaces `.font(.caption)`, `.font(.headline)`, etc. throughout the
    /// app — every call site needs this instead of a raw `Font.TextStyle`
    /// for Settings' Text Size to have any real effect.
    func appFont(_ style: AppFontStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weight: weight))
    }
}

/// Text Size preference, stored once and shared by every SwiftUI surface
/// (Settings window, License sheet, History list) via `\.textScale`.
enum TextSizePreference: String, CaseIterable, Identifiable {
    case small, medium, large, extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.9
        case .medium: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

/// Appearance preference — System follows macOS, Light/Dark force a
/// specific `.preferredColorScheme`.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A small rounded-square, tinted icon tile wrapping a bare SF Symbol —
/// the single "modern & colorful" v2 change (System Settings' own sidebar
/// pattern) that does the most to fix a "monochrome" look. Background is
/// `Color.appAccent` at low opacity; the symbol sits in `Color.appAccent`
/// at roughly 60% of the tile's size.
struct IconTile: View {
    let systemName: String
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(Color.appAccent.opacity(0.15))
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: size * 0.55, weight: .medium))
                    .foregroundStyle(Color.appAccent)
            )
    }
}

/// A rounded-corner card container for grouping related Settings/History
/// content, per the v2 design system (12pt corner radius, 16pt padding,
/// subtle shadow + hairline stroke instead of a flat fill).
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
    }
}

extension View {
    /// Wraps content in a v2 "card" — see `CardBackground`.
    func cardStyle(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

extension Date {
    /// "3 days ago", "2 months ago", "just now", etc.
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
