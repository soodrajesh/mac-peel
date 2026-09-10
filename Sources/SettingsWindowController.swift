import AppKit
import SwiftUI

/// Hosts `SettingsView` (SwiftUI) in a plain `NSWindow` — this app has no
/// SwiftUI `App`/`Scene` lifecycle (it's a pure `NSApplicationDelegate`
/// menu-bar app), so there's no `Settings { }` scene to lean on. A single
/// shared controller keeps ⌘, idempotent: opening it twice just brings the
/// existing window forward instead of spawning a second one.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SnapText Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
