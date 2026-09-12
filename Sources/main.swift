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
    private let permissionDeniedSymbol = "exclamationmark.triangle.fill"

    /// Verified independently of Settings' own check (Settings is a
    /// separate window with no shared SwiftUI environment) — this is the
    /// copy AppKit code (menu building, the capture/gating flow) reads.
    private var isProLicensed = false
    private let licenseChecker = MacPeelLicenseChecker()
    private var licenseRefreshTimer: Timer?

    private var batchImageMenuItem: NSMenuItem?

    /// One-time-per-launch guards so failure alerts don't re-fire on every
    /// single capture attempt once a condition is already known.
    private var hasWarnedAboutDefaultHotKeyFailure = false
    private var hasWarnedAboutScreenRecordingPermission = false
    /// Keyed by `UsageTracker.today` so the cap-hit fallback alert (shown
    /// when notifications aren't authorized) appears at most once per day,
    /// not once per subsequent blocked capture attempt.
    private var lastUpsellAlertDay: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: idleSymbol, accessibilityDescription: "MacPeel: capture screen and copy text")

        buildMenu()
        // Registers with the fixed default until the async license check
        // below resolves, so there's always a working shortcut immediately
        // at launch rather than waiting on a network round trip.
        registerHotKey()

        NotificationCenter.default.addObserver(self, selector: #selector(registerHotKey), name: HotKeyPreference.didChangeNotification, object: nil)

        // Notification permission is requested lazily, in context, the
        // first time the daily cap is actually hit (see `showUpsell()`) —
        // not here at cold launch, before the user has done anything that
        // would explain why a screenshot-OCR menu-bar app wants to send
        // notifications.

        Task {
            await refreshLicense()
            // Custom hotkey remapping is Pro-gated; re-register now that the
            // real license state is known (F6: this previously never ran,
            // so a lapsed Pro user's custom binding kept working silently).
            registerHotKey()
        }

        // Once, at launch — the Settings window's Updates section reads
        // the result back via UpdateState.shared and offers its own
        // "Check for Updates" button to refresh it on demand.
        UpdateState.shared.checkForUpdates()

        // Re-check the license at least once a day independent of the user
        // ever reopening Settings, so a revoked/expired license doesn't
        // leave Pro-only gating (batch OCR, history, custom hotkey) stuck
        // open indefinitely on a long-running install.
        licenseRefreshTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.refreshLicense()
                self?.registerHotKey()
            }
        }
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

        let quitItem = NSMenuItem(title: "Quit MacPeel", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    /// The shortcut actually in effect right now: the user's custom binding
    /// when Pro-licensed, otherwise always the fixed default — matching
    /// what Settings tells the user regardless of what's still sitting in
    /// `HotKeyPreference` from a previous Pro period.
    private func effectiveHotKey() -> (keyCode: UInt32, modifiers: UInt32) {
        isProLicensed
            ? (HotKeyPreference.keyCode, HotKeyPreference.modifiers)
            : (HotKeyPreference.defaultKeyCode, HotKeyPreference.defaultModifiers)
    }

    private func updateCaptureItemKeyEquivalent(_ item: NSMenuItem) {
        // The combo actually registered (may be a fallback), not just the
        // intended one — `HotKeyPreference.active*` is only ever updated on
        // a successful `RegisterEventHotKey` in `registerHotKey()`.
        let keyCode = HotKeyPreference.activeKeyCode
        let modifiers = HotKeyPreference.activeModifiers
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

        let (keyCode, modifiers) = effectiveHotKey()
        hotKey = HotKey(keyCode: keyCode, modifiers: modifiers) { [weak self] in
            self?.capture()
        }

        if hotKey != nil {
            HotKeyPreference.activeKeyCode = keyCode
            HotKeyPreference.activeModifiers = modifiers
        } else {
            // `HotKey.init?` returns nil when `RegisterEventHotKey` fails —
            // e.g. the combo is already claimed globally by macOS or
            // another app. Previously this failed completely silently: the
            // menu showed the combo as active while the global shortcut did
            // nothing.
            let isDefaultCombo = keyCode == HotKeyPreference.defaultKeyCode && modifiers == HotKeyPreference.defaultModifiers
            if !isDefaultCombo {
                // A previously-working custom combo is no longer
                // registrable (another app has since claimed it, etc.) —
                // fall back to the default rather than leaving the user
                // with a dead shortcut and no explanation. This posts
                // `didChangeNotification`, which re-enters this method with
                // the default combo.
                HotKeyPreference.resetToDefault()
            } else {
                // The default itself is claimed by something else, and
                // there's no custom-remap escape hatch for a free user —
                // without this, they'd see "Shortcut Isn't Working" on
                // every single launch forever with no fix short of buying
                // Pro just to pick a different key. Try a short list of
                // alternates instead.
                tryFallbackHotKey()
            }
        }

        if let captureItem = statusItem.menu?.item(withTitle: "Capture Region & OCR") {
            updateCaptureItemKeyEquivalent(captureItem)
        }
    }

    private func tryFallbackHotKey() {
        // Compared against *before* overwriting below — the default is
        // re-probed on every launch (so MacPeel self-heals the moment the
        // conflicting app is removed/updated), but that means this method
        // also re-runs every launch even when nothing has changed. Without
        // this comparison it would re-alert "Shortcut Changed to ⌘⇧U" on
        // every single startup even though it landed on the exact same
        // ⌘⇧U as last time — only a genuine change is worth interrupting
        // the user about.
        let previousKeyCode = HotKeyPreference.activeKeyCode
        let previousModifiers = HotKeyPreference.activeModifiers
        for candidate in HotKeyPreference.fallbackCandidates {
            if let fallback = HotKey(keyCode: candidate.keyCode, modifiers: candidate.modifiers, action: { [weak self] in self?.capture() }) {
                hotKey = fallback
                HotKeyPreference.activeKeyCode = candidate.keyCode
                HotKeyPreference.activeModifiers = candidate.modifiers
                let isUnchanged = candidate.keyCode == previousKeyCode && candidate.modifiers == previousModifiers
                if !isUnchanged && !hasWarnedAboutDefaultHotKeyFailure {
                    hasWarnedAboutDefaultHotKeyFailure = true
                    presentFallbackHotKeyAlert(candidate)
                }
                return
            }
        }
        // Every candidate is also claimed — genuinely unusual; fall back to
        // the old behavior of just explaining the menu-bar icon still works.
        if !hasWarnedAboutDefaultHotKeyFailure {
            hasWarnedAboutDefaultHotKeyFailure = true
            presentDefaultHotKeyFailureAlert()
        }
    }

    private func presentFallbackHotKeyAlert(_ candidate: (keyCode: UInt32, modifiers: UInt32)) {
        let combo = HotKeyPreference.displayString(keyCode: candidate.keyCode, modifiers: candidate.modifiers)
        let alert = NSAlert()
        alert.messageText = "MacPeel's Shortcut Changed to \(combo)"
        alert.informativeText = "MacPeel's default shortcut (⌘⇧O) is already used by another app on this Mac, so MacPeel switched to \(combo) instead. You can still start a capture from the menu bar icon at any time."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentDefaultHotKeyFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "MacPeel's Shortcut Isn't Working"
        alert.informativeText = "MacPeel's default shortcut (⌘⇧O) and its usual alternates are all already used by other apps on this Mac. You can still start a capture from the menu bar icon."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - License

    private func refreshLicense() async {
        let key = UserDefaults.standard.string(forKey: "com.rajeshsood.macpeel.licenseKey") ?? ""
        guard !key.isEmpty else {
            isProLicensed = false
            return
        }
        if OwnerAccess.isOwnerKey(key) {
            isProLicensed = true
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
        showCaptureExplainerIfNeeded()
        isCapturing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            switch ScreenCapture.captureRegion() {
            case .cancelled:
                DispatchQueue.main.async { self?.isCapturing = false } // user pressed Esc
            case .permissionDenied:
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    self?.showScreenRecordingPermissionProblem()
                }
            case .success(let image):
                self?.runOCR(on: [image], source: .regionCapture)
            }
        }
    }

    /// Shown once, the very first time capture is ever attempted, so the
    /// system Screen Recording prompt (attributed to the `screencapture`
    /// helper process, not visibly to "MacPeel") has some in-app context
    /// before it appears.
    private func showCaptureExplainerIfNeeded() {
        let key = "com.rajeshsood.macpeel.hasShownCaptureExplainer"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)

        let alert = NSAlert()
        alert.messageText = "Screen Recording Access"
        alert.informativeText = "MacPeel needs Screen Recording access to capture your screen. macOS may show a permission prompt next — click Allow, then try capturing again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Continue")
        alert.runModal()
    }

    /// Distinct feedback for a Screen-Recording-permission problem, as
    /// opposed to the silent no-op that's correct for an Esc cancel. Flashes
    /// a distinct icon every time (cheap, always useful), and shows a
    /// one-time alert pointing at System Settings the first time it happens
    /// this launch (avoids nagging on every repeated attempt).
    private func showScreenRecordingPermissionProblem() {
        flash(symbol: permissionDeniedSymbol, description: "MacPeel: screen recording permission needed")

        guard !hasWarnedAboutScreenRecordingPermission else { return }
        hasWarnedAboutScreenRecordingPermission = true

        let alert = NSAlert()
        alert.messageText = "Screen Recording Permission Needed"
        alert.informativeText = "MacPeel couldn't capture your screen. Open System Settings → Privacy & Security → Screen Recording, allow access, then try again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
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
        // free tier stays single-image, same as before. `NSOpenPanel` has
        // no subtitle API, so this message is the only place a free user
        // sees *why* ⌘-clicking a second file doesn't do anything.
        panel.allowsMultipleSelection = isProLicensed
        panel.message = isProLicensed
            ? "Choose one or more images to OCR."
            : "Choose an image to OCR. Upgrade to Pro to select multiple images at once."
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK else { return }
        let images = panel.urls.compactMap { NSImage(contentsOf: $0) }
        guard !images.isEmpty else { return }

        isCapturing = true
        runOCR(on: images, source: .chooseImage)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
        Task {
            await refreshLicense()
            registerHotKey()
        }
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
            flash(symbol: emptySymbol, description: "MacPeel: no text found")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if isProLicensed {
            OCRHistoryStore.record(text: text, source: source)
        }
        flash(symbol: successSymbol, description: "MacPeel: text copied")
        sendCopyNotification(text: text)
    }

    /// Confirms a successful copy with a real notification banner showing a
    /// preview of what's now on the clipboard — the 1.2s icon flash in
    /// `flash(symbol:description:)` is easy to miss in peripheral vision and
    /// gives no way to check *what* got copied without pasting first. Free
    /// tier gets this too (unlike history); it's just a copy confirmation,
    /// not a feature worth gating. Opt-out via Settings > General; also
    /// silently skipped if notifications aren't authorized — never falls
    /// back to an in-app alert per capture, since that would be far too
    /// naggy for something this frequent (unlike the once-per-day upsell
    /// alert this deliberately doesn't mirror).
    private func sendCopyNotification(text: String) {
        guard UserDefaults.standard.object(forKey: "com.rajeshsood.macpeel.copyNotifications") as? Bool ?? true else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self.postCopyNotification(text: text)
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
                        if granted {
                            DispatchQueue.main.async { self.postCopyNotification(text: text) }
                        }
                    }
                case .denied:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    private func postCopyNotification(text: String) {
        let preview = text.count > 120 ? String(text.prefix(120)) + "…" : text
        let content = UNMutableNotificationContent()
        content.title = "Text copied"
        content.body = preview
        content.sound = nil
        let request = UNNotificationRequest(identifier: "com.rajeshsood.macpeel.copyConfirmation", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Briefly swaps the menu bar icon to confirm success/failure, then
    /// reverts — the only feedback needed for a one-shot capture-and-copy
    /// action with no window of its own. Every transient state carries a
    /// real `accessibilityDescription` so VoiceOver users can tell success,
    /// empty-result, locked, and permission-denied states apart — previously
    /// all four collapsed to a nil description.
    private func flash(symbol: String, description: String) {
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            self.statusItem.button?.image = NSImage(systemSymbolName: self.idleSymbol, accessibilityDescription: "MacPeel: capture screen and copy text")
        }
    }

    /// The free daily cap was hit: flash a distinct locked-icon state (so
    /// the failure doesn't look like an ordinary "no text found" miss), and
    /// try to fire a local notification pointing at the upgrade path. The
    /// notification is only useful if it's actually authorized to appear —
    /// this checks live authorization status right before sending rather
    /// than trusting a stale result captured once at launch, and falls back
    /// to a one-time-per-day in-app alert when it isn't.
    private func showUpsell() {
        flash(symbol: lockedSymbol, description: "MacPeel: daily limit reached")

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional:
                    self?.sendUpsellNotification()
                case .notDetermined:
                    // Never asked yet — ask now, in context (the cap was
                    // just hit), rather than cold at launch. If the user
                    // grants it, this notification is simply not delivered
                    // this one time; the next cap-hit will use it.
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
                        if granted {
                            DispatchQueue.main.async { self?.sendUpsellNotification() }
                        } else {
                            DispatchQueue.main.async { self?.showUpsellFallbackAlert() }
                        }
                    }
                case .denied:
                    self?.showUpsellFallbackAlert()
                @unknown default:
                    self?.showUpsellFallbackAlert()
                }
            }
        }
    }

    private func sendUpsellNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Daily free limit reached"
        content.body = "You've used all \(UsageTracker.freeDailyLimit) free OCR operations today. Resets at midnight. Unlock MacPeel Pro for unlimited use, batch OCR, history, and custom hotkeys."
        content.sound = nil
        let request = UNNotificationRequest(identifier: "com.rajeshsood.macpeel.upsell", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Durable fallback for when notifications are denied/undetermined and
    /// can't be relied on: a one-time-per-day in-app alert, since the icon
    /// flash alone (1.2s, easy to miss in peripheral vision) was previously
    /// the *only* feedback a user with notifications off ever got.
    private func showUpsellFallbackAlert() {
        guard lastUpsellAlertDay != UsageTracker.today else { return }
        lastUpsellAlertDay = UsageTracker.today

        let alert = NSAlert()
        alert.messageText = "Daily Free Limit Reached"
        alert.informativeText = "You've used all \(UsageTracker.freeDailyLimit) free OCR operations today. This resets at midnight. Unlock MacPeel Pro for unlimited use, batch OCR, history, and custom hotkeys."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Learn About Pro")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(MacPeelLicenseConfig.purchaseURL)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
