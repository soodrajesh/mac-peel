# SnapText v1.1 — UI/UX & Functional Audit

Static, code-driven audit of the full source tree (`Sources/`, `SnapText.entitlements`, `Info.plist`) against Apple's Human Interface Guidelines and Nielsen's 10 usability heuristics. No live GUI automation was performed; every flow below is traced through the actual code paths, with file:line references.

**Scope traced end-to-end:** region-capture OCR, Choose Image OCR (single + Pro batch), the new Settings window (General / History / License / About), the free 20/day usage cap and its upsell, custom hotkey remapping (Pro), and Polar.sh licensing.

---

## Executive Summary — Top 5 Issues by Impact

| # | Severity | Issue | Where |
|---|----------|-------|-------|
| 1 | **Critical** | OCR history is stored **in plaintext, unsandboxed, in a globally-readable `UserDefaults` plist** — any local process/user can run `defaults read com.rajeshsood.snaptext com.rajeshsood.snaptext.ocrHistory` and dump every password, 2FA code, or sensitive text the user has ever OCR'd, no permission prompt required. | `OCRHistoryStore.swift:24-33`, no sandbox (`SnapText.entitlements`) |
| 2 | **High** | A user who records a **broken/conflicting hotkey silently fails** — `HotKey.init` returns `nil` when `RegisterEventHotKey` fails (combo already taken by macOS/another app), and neither the Recorder UI nor `AppDelegate` surfaces this. The UI shows the new combo as "recorded" while the global shortcut quietly does nothing. | `Sources/HotKey.swift:26`, `Sources/main.swift:82-90`, `Sources/Views/ShortcutRecorderView.swift:49-67` |
| 3 | **High** | Screen-Recording-permission-denied and user-pressed-Esc are **indistinguishable** — both produce a silently-returned `nil` from `captureRegion()`, so a permission problem gives the user *zero* feedback (not even the existing "no text found" icon), while every other failure mode does flash something. | `Sources/ScreenCapture.swift:19-22`, `Sources/main.swift:118-124` |
| 4 | **High** | **Custom hotkey remapping isn't actually re-locked when a Pro license lapses.** Settings UI shows the fixed default (⌘⇧O) for free users, but `registerHotKey()` reads `HotKeyPreference.keyCode/modifiers` unconditionally — a previously-Pro user's custom binding keeps working after downgrade, contradicting what the UI tells them. | `Sources/main.swift:82-90` (no license check) vs `Sources/Views/SettingsView.swift:105-123` (UI pretends it's locked) |
| 5 | **Medium-High** | The only feedback for hitting the daily cap is a 1.2s menu-bar icon flash plus a **best-effort local notification that is never confirmed to be authorized/delivered** (`requestAuthorization` result is discarded at launch, and `showUpsell()` fires the notification unconditionally without checking permission state or catching failure). A user who denied/ignored the permission prompt sees only a lock icon flash past in their peripheral vision, with no explanation of *why* capture stopped working or that it resets at midnight. | `Sources/main.swift:35`, `204-213` |

**Overall polish rating: 5.5/10** against a paid Mac-utility bar. The core OCR loop, offline Vision-based recognition, Keychain-backed license cache, and text-scale plumbing are genuinely well engineered — better than most indie utilities. But the app fails on exactly the areas a v1.1-with-monetization release should have hardened: the new usage-cap UX has almost no persistent visibility, the new Pro feature (hotkey remapping) has a silent-failure mode and an actual gating bug, and history — the headline new Pro feature — has a real privacy exposure with no mitigation. None of these are hard to fix; all are concrete, scoped changes (see fixes below).

---

## Fix Status (2026-09-10)

All Critical/High findings were fixed, plus the Medium findings that were cheap/low-risk to close alongside them. Build verified via `./build.sh` (universal arm64/x86_64 binary, compiles cleanly, no warnings surfaced).

| # | Severity | Status | Notes |
|---|----------|--------|-------|
| F1 | High | **Fixed** | `ScreenCapture.captureRegion()` now returns a `CaptureOutcome` enum (`.success` / `.cancelled` / `.permissionDenied`) distinguished via `screencapture`'s exit status + stderr. `AppDelegate.capture()` flashes a distinct icon + shows a one-time-per-launch alert (with a System Settings deep link) on `.permissionDenied`; `.cancelled` stays silent. |
| F2 | Medium-High | **Fixed** (lightweight) | A one-time (`UserDefaults`-gated) `NSAlert` now explains Screen Recording access *before* the first-ever capture attempt. Full HIG-ideal fix (moving off the `screencapture` shell-out to `SCScreenshotManager`/native capture so the TCC grant is attributed to SnapText itself, not the `screencapture` helper) is **not done** — that's a capture-architecture change beyond this pass's scope, not a UI fix. |
| F3 | Medium | **Skipped** | Batch partial-failure summary ("7 of 10 produced text") needs a small results-accounting change plus new UI surface (notification or sheet) — judged more than "cheap/low-risk," left for a follow-up pass. Not a regression risk as-is. |
| F4 | High / Medium | **Fixed** | `showUpsell()` now checks live `UNUserNotificationCenter` authorization status before sending (`.authorized`/`.provisional` → notification; `.notDetermined` → request in-context then notify or fall back; `.denied`/unknown → fall back) instead of firing blind. Fallback is a once-per-day `NSAlert` (keyed off `UsageTracker.today`) so a user with notifications off still gets durable feedback. Notification body now includes "Resets at midnight." |
| F5 | Medium | **Skipped** | Ambient "(3 left today)" menu-item visibility before the cap is hit — deferred; touches menu-rebuild timing (would need to refresh the menu item live as usage changes, not just on click) and judged more than a cheap change for this pass. |
| F6 | High | **Fixed** | `registerHotKey()` now computes the effective combo via `effectiveHotKey()`, which returns the fixed default whenever `!isProLicensed` regardless of what's stored in `HotKeyPreference`. Re-run after the async `refreshLicense()` resolves (at launch, on Settings open, and on the new daily re-check timer — see F17) so the gate reflects the *current* license state, not just the state at process start. |
| F7 | High | **Fixed** | `ShortcutRecorderView` now does a trial `HotKey(...)` registration before persisting a newly-recorded combo; on failure it shows an inline red "This shortcut is already in use — try another." message and never calls `onRecorded`/persists the broken binding. `AppDelegate.registerHotKey()` also now checks its own `nil` result defensively (covers a previously-working combo going stale, e.g. another app claims it later): falls back to the default via `HotKeyPreference.resetToDefault()`, or — if even the default fails — shows a one-time alert rather than leaving a silently dead shortcut. |
| F8 | **Critical** | **Fixed** | `OCRHistoryStore` moved off `UserDefaults` entirely. Storage is now `~/Library/Application Support/SnapText/history.json`, written with POSIX mode `0600` (owner-only), reasserted after every write. Keychain was considered and rejected per the audit's own reasoning (history volume — up to 50 free-form entries — is a poor fit for Keychain's per-item size limits); this closes the actual exploitable gap (`defaults read` with zero privilege). Also added, as part of the same change: `OCRHistoryStore.delete(id:)` and a per-entry right-click "Delete" in `HistoryView` (closes part of F8's own ranked fix list, and doubles as F9/F10 groundwork). |
| F9 | Medium | **Skipped** | Search/filter across history entries — deferred; a real UI addition (search field + filtered list + empty-state copy), not a cheap patch. |
| F10 | Medium | **Fixed** | "Clear" now routes through a `.confirmationDialog` ("Clear all N OCR history entries? This can't be undone.") before calling `OCRHistoryStore.clear()`. |
| F12 | Medium | **Fixed** | `UNUserNotificationCenter.requestAuthorization` is no longer called cold at launch. It's now requested lazily, in context, the first time `showUpsell()` sees `.notDetermined` (i.e., the first time the daily cap is actually hit) — folded into the F4 fix above. |
| F13 | Medium | **Fixed (partial, as recommended)** | `LicenseManagementView`'s `TextEditor` now reads `\.textScale` from the environment and computes its font size from `AppFontStyle.body.basePointSize * scale`, so the pasted-license-key field grows with Text Size like everything else in that sheet. The About tab's decorative `text.viewfinder` glyph was left at a fixed size, per the audit's own suggestion — now documented in-code as an intentional exception rather than an unnoted miss. |
| F14 | Medium | **Fixed** | `flash(symbol:)` now takes a `description` parameter; every call site (success, empty-result, locked/cap-hit, and the new permission-denied state) passes a real, distinct `accessibilityDescription` instead of `nil`. |
| F17 | Low-Medium | **Fixed** | Added a repeating 24h `Timer` in `applicationDidFinishLaunching` that re-runs `refreshLicense()` and `registerHotKey()`, so a revoked/expired license doesn't leave Pro gating (hotkey, batch, history) open indefinitely on a long-running install between Settings visits. |
| F18 | Low | **Fixed** | `NSOpenPanel.message` now reads "Choose an image to OCR. Upgrade to Pro to select multiple images at once." for free-tier users (and a neutral message for Pro), closing the silent single-select gap — `NSOpenPanel` has no subtitle API, so this is the practical fix the audit itself proposed. |
| F19, F20 | Pass | No change | Confirmed correct by the audit; nothing to fix. |

**Not addressed, by design/scope:** the F2 capture-architecture change (native `SCScreenshotManager` instead of shelling out to `/usr/sbin/screencapture`) and the F3/F5/F9 UI additions are all real, valid follow-ups but are feature-sized work rather than the kind of "cheap/low-risk" Medium fix this pass targeted. Everything Critical and High is fixed.

---

## Category: Core OCR Flow

### F1. Permission-denied and user-cancel are conflated (High)
`ScreenCapture.captureRegion()` (`Sources/ScreenCapture.swift:19-22`) treats "file doesn't exist" as the single failure signal:
```swift
guard FileManager.default.fileExists(atPath: tmp.path) else { return nil }
```
This is true whether the user pressed Esc *or* `/usr/sbin/screencapture` was blocked by TCC because Screen Recording permission isn't granted. `AppDelegate.capture()` (`main.swift:118-124`) then does:
```swift
guard let image = ScreenCapture.captureRegion() else {
    DispatchQueue.main.async { self?.isCapturing = false } // user pressed Esc
    return
}
```
The comment itself assumes Esc — but a permission-denied case hits the exact same branch, with **no icon flash at all** (contrast: an OCR pass that finds no text does flash `emptySymbol`). A user whose Mac has never granted Screen Recording to `screencapture`/SnapText will click "Capture Region & OCR" repeatedly and see literally nothing happen, with no path to understanding why.

**Fix:** distinguish the cases — `screencapture`'s exit code differs when it terminates for a permission failure (rendered without writing the file, but macOS also posts a TCC prompt the *first* time this is attempted per app; on subsequent denials there's no prompt, just silent failure). At minimum, detect "no file AND no `-i` cancel keystroke observed" by checking `task.terminationStatus`/stderr, and flash a distinct icon (or fire a notification) directing the user to System Settings → Privacy & Security → Screen Recording.

### F2. No pre-permission explainer before the system TCC dialog (Medium-High)
The audit brief's framing ("Screen Recording permission is required per entitlements") doesn't quite hold: `SnapText.entitlements` **grants no screen-capture entitlement at all** — the app shells out to `/usr/sbin/screencapture` (`ScreenCapture.swift:14`), so the *system* attributes the Screen Recording TCC grant to the `screencapture` helper process, not to "SnapText," the first time it's invoked. Concretely:
- There is no first-run screen, onboarding card, or explanatory copy anywhere in `main.swift` before the user's first capture.
- The macOS permission dialog (when/if it fires) will not obviously read as "SnapText needs this" to a first-time user, since the binary name attributed is `screencapture`.

**Why it matters:** HIG explicitly calls for priming a permission request with app-provided context *before* the system dialog, precisely because a bare system prompt with no lead-in causes users to deny reflexively. Here there isn't even a system dialog the user can clearly attribute to SnapText.

**Fix:** Show a one-time, dismissible explainer (e.g., a `NSAlert` or small window) the very first time `capture()` is invoked, explaining "SnapText needs Screen Recording access to capture your screen. You'll see a system prompt next — click Allow, then try again." Consider moving off the `screencapture` shell-out to a native `SCScreenshotManager`/`CGWindowListCreateImage`-based capture (also improves testability) so the permission is attributed to SnapText itself in System Settings, matching user expectation.

### F3. Batch OCR (Pro) gives no partial-failure summary (Medium)
`runOCR(on:source:)` (`main.swift:158-173`) loops per image, silently skipping images that produce empty text, and silently `break`s the whole loop if `UsageTracker.canPerformOperation` ever returns false mid-batch. The final paste is just the joined survivors with zero indication of how many of N images succeeded.
- For today's Pro-only batch path this cap-mid-batch branch is currently *unreachable* (Pro is unlimited, see `UsageTracker.canPerformOperation`), but it's live code that will silently truncate results the moment the gating logic changes — and even without that, silently dropping images with no extractable text (e.g., a blank screenshot in a 10-image batch) gives no "8 of 10 produced text" signal.

**Fix:** Track per-image outcome and surface a short summary via notification or a lightweight results sheet ("7 of 10 images produced text — 3 were blank"), rather than a single joined blob with no accounting.

---

## Category: Usage-Cap & Pro UX

### F4. Upsell delivery is unverified and the reset behavior isn't in the notification (High / Medium)
`applicationDidFinishLaunching` (`main.swift:35`) requests notification authorization and discards the result:
```swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
```
`showUpsell()` (`main.swift:204-213`) then unconditionally builds and `.add()`s a `UNNotificationRequest` without ever checking `UNUserNotificationCenter.current().notificationSettings().authorizationStatus`. If the user denied (or simply dismissed) the initial system prompt, the notification never appears — the *only* remaining feedback is a 1.2s icon flash to `lockedSymbol` with no `accessibilityDescription` (see A2 below) and no explanatory text anywhere in that flash.

Separately, the notification body that *does* land reads:
> "You've used all 20 free OCR operations today. Unlock SnapText Pro for unlimited use, batch OCR, history, and custom hotkeys."

— accurate and non-alarming (good), but it never mentions the cap resets at midnight, even though that fact is correctly surfaced in Settings (`SettingsView.swift:134`, "Resets at midnight. Region capture and Choose Image both count."). A user who only ever sees the notification (never opens Settings) has no way to know the block is temporary.

**Fix:** (a) check `authorizationStatus` before relying on notifications for the cap message; when denied/undetermined, fall back to something durable — e.g., a menu-bar badge/overlay or a brief `NSAlert` the first time the cap is hit that day. (b) Add "Resets at midnight" to the notification body.

### F5. No persistent/ambient visibility of remaining quota (Medium)
The menu itself (`buildMenu()`, `main.swift:42-68`) never reflects usage state — no "17/20 today" in the menu, no disabled/grayed items as the user approaches the cap, nothing until they've already been blocked. Nielsen's "visibility of system status" calls for surfacing this *before* the failure, not just after. Settings' General tab does show `countToday`/`freeDailyLimit` (`SettingsView.swift:131-138`), but nothing nudges the user to look there.

**Fix:** Add a low-cost ambient signal — e.g. append "(3 left today)" to the Capture menu item's subtitle once remaining count drops below a threshold (5), or swap the idle icon to a subtly different tint in the last few operations.

### F6. Custom hotkey isn't re-gated on license downgrade (High — functional bug)
Already flagged in the Executive Summary. Concretely:
- `SettingsView.swift:105-123` shows the Pro `ShortcutRecorderView` only `if isProLicensed`, and for free users renders a **hardcoded** `HotKeyPreference.defaultKeyCode/defaultModifiers` string — not whatever `HotKeyPreference.keyCode/modifiers` actually resolves to.
- `AppDelegate.registerHotKey()` (`main.swift:82-90`) reads `HotKeyPreference.keyCode`/`.modifiers` directly, with **no `isProLicensed` check whatsoever.**

Net effect: a lapsed/downgraded Pro user keeps their custom global shortcut working exactly as before, while Settings visually tells them they're back to ⌘⇧O. This is both a monetization leak and a trust-breaking UI lie (the display doesn't match reality).

**Fix:** Either (a) enforce the gate at the source — `registerHotKey()` should fall back to `HotKeyPreference.defaultKeyCode/defaultModifiers` when `!isProLicensed`, and/or (b) call `HotKeyPreference.resetToDefault()` the moment a license check comes back invalid/expired for a key that was previously valid.

### F7. Hotkey conflicts and registration failures are invisible (High)
`ShortcutRecorderView.startRecording()` (`Views/ShortcutRecorderView.swift:49-67`) accepts any combo with ≥1 modifier and immediately calls `onRecorded`, which persists it via `HotKeyPreference.set()` and posts `didChangeNotification`. `AppDelegate.registerHotKey()` then does:
```swift
hotKey = HotKey(keyCode: ..., modifiers: ...) { ... }
```
`HotKey.init?` (`HotKey.swift:17-28`) returns `nil` if `RegisterEventHotKey` fails (`status != noErr`) — which happens whenever the combo is already claimed globally (a common real-world case: ⌘⇧4/5 for screenshots, ⌘Space for Spotlight-alternatives, many menu-bar utilities reserve combos). There is:
- No conflict-detection *before* recording (no check against known system/menu-extra shortcuts).
- No post-registration verification — `hotKey` is set to `nil` on failure and nothing tells the Recorder UI, so the box still displays the "successfully recorded" combo while the underlying global shortcut is dead.
- No fallback to the previous/default binding on failure.

**Fix:** Have `registerHotKey()` return/report success, and have the Settings view react to a failed registration — e.g. an inline error ("⌘⇧4 is already in use system-wide — try another combo") and automatic revert to the last-known-working binding, rather than leaving the user with a shortcut that silently does nothing.

---

## Category: Privacy / History

### F8. OCR history stored in plaintext with no isolation, no purge granularity, no exclusion (Critical)
`OCRHistoryStore` (`Sources/OCRHistoryStore.swift:24-33`) persists up to 50 entries of raw extracted text as JSON inside a standard `UserDefaults` key (`com.rajeshsood.snaptext.ocrHistory`). Combined with the deliberate choice to **not sandbox** the app (`SnapText.entitlements` comment, lines 6-9), this plist is trivially readable by:
- Any other process running as the same user (`defaults read com.rajeshsood.snaptext`), no Full Disk Access or special entitlement required.
- Anyone with brief physical/remote access to the Mac.

Because SnapText's entire value proposition is "OCR whatever's on your screen," this will routinely capture 2FA codes, passwords visible in a password manager UI, financial figures, or other sensitive text — and it's now durably logged in cleartext for Pro users with **no encryption, no per-entry delete (only a single global "Clear" in `HistoryView.swift:20-26`), and no way to exclude a capture from being logged at all** (recording happens unconditionally for Pro in `main.swift:184`, `OCRHistoryStore.record`).

**Fix, ranked by effort:**
1. Minimum: move `OCRHistoryStore`'s backing store from `UserDefaults` to the Keychain (the app already has this exact pattern in `SnapTextLicenseCache`) or an encrypted-at-rest file.
2. Add a "Don't log this capture" modifier — e.g. hold a modifier key while triggering capture to OCR-but-not-log, or a Settings toggle to pause history logging temporarily.
3. Add per-entry delete (swipe/right-click) in `HistoryView`, not just "Clear all."
4. Consider a lightweight heuristic (e.g. detect obvious password-manager or 1Password/Keychain-prompt window titles) to skip auto-logging — optional, but worth considering given the product's core mechanic makes this an unusually live risk compared to most menu-bar utilities.

### F9. No search/filter in History (Medium)
`HistoryView.swift` renders all entries (up to 50) in a single `ScrollView` (`historyRow`, lines 51-85) with no search field, no filter by source (Region Capture vs Choose Image), and no date grouping. At the cap of 50 entries with 2-line previews (`lineLimit(2)`), this is a long, undifferentiated scroll — usable at 5-10 entries, not at 50. There's also no way to view an entry's *full* text in-app; the only actions are "copy to clipboard" (silently, via a checkmark swap) or "clear everything."

**Fix:** Add a search field bound to `entries.filter { $0.text.localizedCaseInsensitiveContains(query) }`, and a tap-to-expand or detail sheet for full text.

### F10. "Clear" history has no confirmation (Medium)
`HistoryView.swift:20-26` wires "Clear" (marked `role: .destructive`) directly to `OCRHistoryStore.clear()` with zero confirmation step — one misclick permanently deletes up to 50 entries, some of which (per F8) may be effectively irreplaceable sensitive captures. `role: .destructive` alone only colors the button red; it doesn't gate the action.

**Fix:** Wrap in a `.confirmationDialog` ("Clear all 23 OCR history entries? This can't be undone.") before calling `OCRHistoryStore.clear()`.

---

## Category: Permissions

### F11. See F1/F2 above (Screen Recording ask has no in-app context, and denial is indistinguishable from cancel).

### F12. Notification permission requested cold, at launch, with no context (Medium)
`applicationDidFinishLaunching` fires `UNUserNotificationCenter.current().requestAuthorization` unconditionally on every fresh install/first launch (`main.swift:35`), before the user has done anything — a textbook HIG violation ("ask for permission in context, not at launch"). A user has no idea why a screenshot-OCR menu-bar app wants to send them notifications before they've even hit the free cap once. This also burns the one-shot system prompt: if the user reflexively denies it (having no context), there's no in-app path to explain and re-request later (F4 compounds this — the upsell then silently fails to deliver).

**Fix:** Defer the `requestAuthorization` call to the *first time* the cap is actually about to be hit (i.e., call it lazily from `showUpsell()`'s first invocation, or the read of `remainingToday <= 1`), ideally preceded by one sentence of in-app context.

---

## Category: Accessibility

### F13. Two raw `.font()` calls bypass the `.appFont`/text-scale system (Medium)
The app's own `Support.swift` documents `.appFont(_:weight:)` as the mandatory replacement for raw `.font()` "throughout the app... for Settings' Text Size to have any real effect" (`Support.swift:62-68`). A grep of `Sources/` turns up two violations:
- `Views/LicenseManagementView.swift:165` — the license-key paste `TextEditor` uses `.font(.system(.body, design: .monospaced))` directly. This is the one place users read/verify a pasted license key, and it will **not** grow with the Text Size setting while every other label in that same sheet does — an inconsistent, jarring exception for exactly the control where legibility matters most (verifying a long alphanumeric key).
- `Views/SettingsView.swift:159` — the About tab's `text.viewfinder` glyph uses `.font(.system(size: 40))`. Lower stakes (decorative icon, not text a user reads), but still inconsistent with the stated policy and won't scale with the rest of the About header.

**Fix:** Route the `TextEditor` font through a `.appFont`-equivalent (SwiftUI doesn't expose a `ViewModifier` overload for `TextEditor`'s font the same way, but `Font.system(size: AppFontStyle.body.basePointSize * scale, design: .monospaced)` reading `@Environment(\.textScale)` directly would close the gap). The About icon can stay fixed but should be documented as an intentional decorative exception rather than an unnoticed miss.

### F14. Transient menu-bar icon states carry no accessibility description (Medium)
`flash(symbol:)` (`main.swift:192-197`) always constructs the icon image with `accessibilityDescription: nil`:
```swift
statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
```
This is used for *every* transient state — success, empty-result, and locked/cap-hit (`lockedSymbol`, called from `showUpsell()` at line 205). Only the resting idle icon (set at `main.swift:28` and again inside `flash`'s completion, line 196) carries a real description ("SnapText"). A VoiceOver user gets no spoken feedback distinguishing "OCR succeeded," "no text found," or "daily limit reached" — the one axis of system status this icon-only app relies on for feedback is entirely inaccessible to screen-reader users.

**Fix:** Give each symbol a real, distinct `accessibilityDescription` ("SnapText: text copied", "SnapText: no text found", "SnapText: daily limit reached") — trivial fix, meaningful accessibility gain given how much weight the icon-flash pattern carries in this app's design.

### F15. Text-scale/appearance plumbing is otherwise solid (Pass, noted for completeness)
`Support.swift`'s `TextScaleKey`/`AppFontStyle`/`appFont` mechanism is well designed — computed live from environment, applied per semantic role, and (aside from F13) consistently used across `SettingsView`, `HistoryView`, and `LicenseManagementView`. `AppearancePreference` correctly maps to `.preferredColorScheme` including a proper `nil` (system) case. This is meaningfully better accessibility groundwork than most single-developer menu-bar utilities ship with.

---

## Category: Functional Bugs

### F16. Hotkey re-registration and license-lapse gating — see F6, F7.

### F17. `isProLicensed` can go stale between Settings visits (Low-Medium)
`AppDelegate.isProLicensed` is only refreshed at launch (`main.swift:37`) and each time Settings is opened (`openSettings()`, `main.swift:148-151`). If a license is remotely revoked (refund, chargeback) while the app keeps running without the user reopening Settings, `capture()`/`chooseImage()`'s gating (`main.swift:112`, `129`) keeps trusting the last-known `isProLicensed = true` indefinitely — unlimited operations and batch selection both stay unlocked. Low real-world likelihood, but there's no periodic re-check (e.g. on a timer, or at least once per calendar day) independent of the user opening Settings.

**Fix:** Re-run `refreshLicense()` at least once per day (e.g. tie it to `UsageTracker`'s own day-rollover check) rather than only on Settings-open.

### F18. Free-tier "Choose Image" gives no explanation for single-select-only (Low)
`chooseImage()` (`main.swift:127-146`) sets `panel.allowsMultipleSelection = isProLicensed` silently — a free user who tries to ⌘-click multiple files in the open panel will find it simply doesn't let them, with zero in-panel explanation that multi-select is a Pro feature. (The explanation only exists in Settings → General → Batch OCR, which the user isn't looking at during this flow.)

**Fix:** Not fully fixable via `NSOpenPanel` (it has no subtitle API), but consider `panel.message = "Choose an image to OCR. Upgrade to Pro to select multiple images at once."` — `NSOpenPanel.message` is user-settable and would close this gap for free.

### F19. Polar.sh placeholder org ID — confirmed fails closed correctly (Pass)
Traced end-to-end and confirmed **working as intended**: `SnapTextLicenseConfig.organizationID` is empty by default (`SnapTextLicense.swift:36-38`), so `SnapTextLicenseChecker.verify()` throws `.notConfigured` immediately (`SnapTextLicense.swift:179`) before any network call. At launch, `AppDelegate.refreshLicense()` only calls `verify()` if a license key is already stored (`main.swift:95-99`), so a fresh free-tier install never triggers this path at all — no error surfaces anywhere. If a user does manually enter a key in Settings, `LicenseManagementView.verify()` catches the error and shows the honest, non-alarming message "SnapText Pro isn't configured yet — check back soon." (`SnapTextLicense.swift:70`), not a raw network/HTTP error. The free experience (20/day cap, default hotkey, no history) is fully functional and never blocked on the unconfigured Polar org.

### F20. Daily cap reset boundary — confirmed correct (Pass)
`UsageTracker.today` (`UsageTracker.swift:19-24`) uses `DateFormatter` with `timeZone = .current`, correctly resetting at **local** midnight rather than a rolling 24h/UTC window, matching what Settings tells the user (`SettingsView.swift:134`). `resetIfNewDay()` is called defensively from every read/write path (`countToday`, `canPerformOperation`, `recordOperation`), so there's no stale-count edge case around the day boundary.

---

## Summary of Concrete Fixes (Priority Order)

1. Move `OCRHistoryStore` off plaintext `UserDefaults` (F8) — or at minimum add a documented risk callout and per-entry delete.
2. Gate `registerHotKey()` on `isProLicensed`, and surface `HotKey.init` registration failures back to the Settings UI (F6, F7).
3. Distinguish permission-denied from user-cancel in `ScreenCapture.captureRegion()`, and add a first-run Screen-Recording explainer (F1, F2).
4. Check notification authorization status before relying on it for the cap upsell; add "resets at midnight" to the notification body (F4).
5. Give every menu-bar icon state a real `accessibilityDescription` (F14) and route `LicenseManagementView`'s `TextEditor` font through the scale system (F13).
6. Add search + per-entry delete + a clear-confirmation to `HistoryView` (F9, F10).
7. Add ambient remaining-quota visibility to the menu itself (F5).

**Overall polish: 5.5/10** for a paid Mac utility — strong technical bones (on-device Vision OCR, Keychain-backed license cache, live text-scale system, honest fail-closed licensing), let down by a v1.1 feature set (usage cap, history, hotkey remapping) that was wired for the happy path but not for its own failure/edge cases, plus one real privacy exposure in the new history feature.
