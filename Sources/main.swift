import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var isCapturing = false

    private let idleSymbol = "text.viewfinder"
    private let successSymbol = "checkmark.circle.fill"
    private let emptySymbol = "questionmark.circle"
    private let lockedSymbol = "lock.circle"

    /// Verified independently of Settings' own check (Settings is a
    /// separate window with no shared SwiftUI environment) — this is the
    /// copy AppKit code (menu building, the capture/gating flow) reads.
    private var isProLicensed = false
    private let licenseChecker = SnapTextLicenseChecker()

    private var batchImageMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: idleSymbol, accessibilityDescription: "SnapText")

        buildMenu()
        registerHotKey()

        NotificationCenter.default.addObserver(self, selector: #selector(registerHotKey), name: HotKeyPreference.didChangeNotification, object: nil)

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }

        Task { await refreshLicense() }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let captureItem = NSMenuItem(title: "Capture Region & OCR", action: #selector(capture), keyEquivalent: "")
        captureItem.target = self
        updateCaptureItemKeyEquivalent(captureItem)
        menu.addItem(captureItem)

        let openImageItem = NSMenuItem(title: "Choose Image…", action: #selector(chooseImage), keyEquivalent: "")
        openImageItem.target = self
        menu.addItem(openImageItem)
        batchImageMenuItem = openImageItem

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SnapText", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func updateCaptureItemKeyEquivalent(_ item: NSMenuItem) {
        let keyCode = HotKeyPreference.keyCode
        let modifiers = HotKeyPreference.modifiers
        item.keyEquivalent = HotKeyPreference.label(forKeyCode: keyCode).lowercased()
        var mask: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { mask.insert(.command) }
        if modifiers & UInt32(shiftKey) != 0 { mask.insert(.shift) }
        if modifiers & UInt32(optionKey) != 0 { mask.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { mask.insert(.control) }
        item.keyEquivalentModifierMask = mask
    }

    @objc private func registerHotKey() {
        hotKey = nil // drop the old registration before installing a new one
        hotKey = HotKey(keyCode: HotKeyPreference.keyCode, modifiers: HotKeyPreference.modifiers) { [weak self] in
            self?.capture()
        }
        if let captureItem = statusItem.menu?.item(withTitle: "Capture Region & OCR") {
            updateCaptureItemKeyEquivalent(captureItem)
        }
    }

    // MARK: - License

    private func refreshLicense() async {
        let key = UserDefaults.standard.string(forKey: "com.rajeshsood.snaptext.licenseKey") ?? ""
        guard !key.isEmpty else {
            isProLicensed = false
            return
        }
        do {
            let license = try await licenseChecker.verify(licenseKey: key)
            isProLicensed = license.isValid
        } catch {
            isProLicensed = false
        }
    }

    // MARK: - Actions

    @objc private func capture() {
        guard !isCapturing else { return }
        guard UsageTracker.canPerformOperation(isProLicensed: isProLicensed) else {
            showUpsell()
            return
        }
        isCapturing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = ScreenCapture.captureRegion() else {
                DispatchQueue.main.async { self?.isCapturing = false } // user pressed Esc
                return
            }
            self?.runOCR(on: [image], source: .regionCapture)
        }
    }

    @objc private func chooseImage() {
        guard !isCapturing else { return }
        guard UsageTracker.canPerformOperation(isProLicensed: isProLicensed) else {
            showUpsell()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        // Batch OCR (selecting several images at once) is a Pro feature —
        // free tier stays single-image, same as before.
        panel.allowsMultipleSelection = isProLicensed
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        let images = panel.urls.compactMap { NSImage(contentsOf: $0) }
        guard !images.isEmpty else { return }

        isCapturing = true
        runOCR(on: images, source: .chooseImage)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
        Task { await refreshLicense() }
    }

    /// Shared tail end of both entry points: hash out to a background queue
    /// so Vision's `.accurate` pass never blocks the main thread, then hop
    /// back to update the icon. Runs each image in `images` in sequence
    /// (Pro's batch picker can hand this more than one) and joins the
    /// results, respecting the free-tier cap per image.
    private func runOCR(on images: [NSImage], source: OCRHistoryEntry.Source) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var results: [String] = []
            for image in images {
                guard UsageTracker.canPerformOperation(isProLicensed: self.isProLicensed) else { break }
                let text = OCRService.recognize(image)
                UsageTracker.recordOperation(isProLicensed: self.isProLicensed)
                if !text.isEmpty { results.append(text) }
            }
            let combined = results.joined(separator: "\n\n")
            DispatchQueue.main.async {
                self.finish(text: combined, source: source)
            }
        }
    }

    private func finish(text: String, source: OCRHistoryEntry.Source) {
        isCapturing = false
        guard !text.isEmpty else {
            flash(symbol: emptySymbol)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if isProLicensed {
            OCRHistoryStore.record(text: text, source: source)
        }
        flash(symbol: successSymbol)
    }

    /// Briefly swaps the menu bar icon to confirm success/failure, then
    /// reverts — the only feedback needed for a one-shot capture-and-copy
    /// action with no window of its own.
    private func flash(symbol: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = NSImage(systemSymbolName: self.idleSymbol, accessibilityDescription: "SnapText")
        }
    }

    /// The free daily cap was hit: flash a distinct locked-icon state (so
    /// the failure doesn't look like an ordinary "no text found" miss) and
    /// fire a brief local notification pointing at the upgrade path,
    /// rather than silently doing nothing.
    private func showUpsell() {
        flash(symbol: lockedSymbol)

        let content = UNMutableNotificationContent()
        content.title = "Daily free limit reached"
        content.body = "You've used all \(UsageTracker.freeDailyLimit) free OCR operations today. Unlock SnapText Pro for unlimited use, batch OCR, history, and custom hotkeys."
        content.sound = nil
        let request = UNNotificationRequest(identifier: "com.rajeshsood.snaptext.upsell", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
