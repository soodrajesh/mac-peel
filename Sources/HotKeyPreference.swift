import Carbon.HIToolbox
import AppKit

/// The user-configurable global capture shortcut. Free tier is locked to
/// the default ⌘⇧O; custom remapping is a Pro feature (see
/// `Views/SettingsView.swift`). Stored in `UserDefaults` directly (not
/// `@AppStorage`) since it needs to be read from `AppDelegate`, plain
/// AppKit code with no SwiftUI environment.
enum HotKeyPreference {
    /// kVK_ANSI_O
    static let defaultKeyCode: UInt32 = 31
    static let defaultModifiers: UInt32 = UInt32(cmdKey | shiftKey)

    private static let keyCodeKey = "com.rajeshsood.snaptext.hotKeyCode"
    private static let modifiersKey = "com.rajeshsood.snaptext.hotKeyModifiers"

    /// Posted whenever the shortcut changes, so `AppDelegate` can
    /// re-register the global hotkey without a relaunch.
    static let didChangeNotification = Notification.Name("com.rajeshsood.snaptext.hotKeyDidChange")

    static var keyCode: UInt32 {
        let stored = UserDefaults.standard.object(forKey: keyCodeKey) as? Int
        return stored.map(UInt32.init) ?? defaultKeyCode
    }

    static var modifiers: UInt32 {
        let stored = UserDefaults.standard.object(forKey: modifiersKey) as? Int
        return stored.map(UInt32.init) ?? defaultModifiers
    }

    static func set(keyCode: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: keyCodeKey)
        UserDefaults.standard.removeObject(forKey: modifiersKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static var isCustomized: Bool {
        keyCode != defaultKeyCode || modifiers != defaultModifiers
    }

    /// A small, readable subset of `kVK_ANSI_*` codes — enough to label
    /// letters/digits for the recorder UI and the menu item's key
    /// equivalent. Falls back to "Key <code>" for anything outside this
    /// table (function keys, arrows, etc. can still be *bound*, via the
    /// raw `NSEvent`, just shown less prettily).
    private static let keyCodeLabels: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 25: "9", 26: "7", 28: "8", 29: "0",
        31: "O", 32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
        24: "=", 27: "-", 33: "[", 30: "]", 39: "'", 41: ";", 42: "\\", 43: ",", 44: "/", 47: ".", 50: "`"
    ]

    static func label(forKeyCode code: UInt32) -> String {
        keyCodeLabels[code] ?? "Key \(code)"
    }

    /// e.g. "⌘⇧O" — matches how macOS itself renders modifier + key.
    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var symbols = ""
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols + label(forKeyCode: keyCode)
    }

    /// Converts an `NSEvent.ModifierFlags` (from a local key-down monitor
    /// used while recording a new shortcut) into the Carbon modifier mask
    /// `RegisterEventHotKey` expects.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }
}
