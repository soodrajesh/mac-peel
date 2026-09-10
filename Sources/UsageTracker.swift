import Foundation

/// Free-tier daily usage cap for OCR operations (region capture + Choose
/// Image both count against the same counter). Pro is unlimited.
///
/// Backed by two `UserDefaults` keys — a count and the calendar day it
/// belongs to — rather than `@AppStorage` directly in a View, since the
/// cap needs to be checked from `AppDelegate` (AppKit, not SwiftUI) at the
/// moment a capture starts, not just displayed in Settings.
enum UsageTracker {
    static let freeDailyLimit = 20

    private static let countKey = "com.rajeshsood.snaptext.usage.count"
    private static let dayKey = "com.rajeshsood.snaptext.usage.day"

    /// "2026-09-10" in the user's local calendar — used as the reset
    /// boundary so the cap resets at local midnight, not a rolling 24h
    /// window.
    private static var today: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }

    private static func resetIfNewDay() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: dayKey) != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: countKey)
        }
    }

    /// Today's OCR operation count so far.
    static var countToday: Int {
        resetIfNewDay()
        return UserDefaults.standard.integer(forKey: countKey)
    }

    /// Whether another free-tier OCR operation is allowed right now.
    /// Always `true` for Pro — callers should check `isProLicensed` first
    /// and skip calling this at all when Pro, but it's safe either way.
    static func canPerformOperation(isProLicensed: Bool) -> Bool {
        isProLicensed || countToday < freeDailyLimit
    }

    /// Records that one OCR operation just ran. No-op for Pro, since the
    /// counter only exists to enforce the free cap.
    static func recordOperation(isProLicensed: Bool) {
        guard !isProLicensed else { return }
        resetIfNewDay()
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }

    static var remainingToday: Int {
        max(0, freeDailyLimit - countToday)
    }
}
