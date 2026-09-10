# SnapText Audit — 2026-09-10

## Build
**Status: PASS (clean).**
- `./build.sh` completes successfully: compiles both `arm64` and `x86_64` slices, lipo's them into a universal binary, renders the app icon from an SF Symbol, code-signs with the Developer ID Application identity found in the keychain, and installs to `/Applications`.
- Cross-checked with a direct `swiftc -O` compile of `Sources/*.swift` — zero warnings, zero errors.
- No source changes were needed; nothing to fix.

## Tests
**Status: none present.** No `Tests/` directory, no `Package.swift`/SwiftPM test target, no `Tests/run_tests.sh`. Nothing to run.

## Audit findings

- **Crashes / force-unwraps / TODOs**: none found. `grep -rn "TODO\|FIXME\|XXX"` over `Sources/` is empty. The only implicitly-unwrapped optional is `statusItem: NSStatusItem!` in `main.swift`, which is always assigned before use in `applicationDidFinishLaunching` — a standard, safe AppDelegate pattern, not a latent crash.
- **App icon states**: the app icon and every menu-bar state (idle `text.viewfinder`, success `checkmark.circle.fill`, empty-result `questionmark.circle`) are all SF Symbols — no placeholder or missing icon assets. The `.icns` is generated at build time from the same symbol family used in the menu bar, so the two are visually consistent by construction.
- **SF Symbols vs custom assets**: fully consistent — the app uses SF Symbols exclusively (no custom asset catalog, no bitmap icon files checked into source). Nothing to reconcile.
- **Entitlements sanity**: `SnapText.entitlements` deliberately omits App Sandbox (this is a direct-distribution DMG app, not App Store) and explicitly sets the three hardened-runtime exemptions (`allow-jit`, `disable-library-validation`, `disable-executable-page-protection`) to `false`, none of which the app needs. Cross-checked against actual capability usage:
  - Screen capture goes through the `/usr/sbin/screencapture` subprocess (inherits the system Screen Recording TCC prompt; needs no entitlement).
  - OCR uses on-device Vision (`VNRecognizeTextRequest`); no network, no entitlement required.
  - The global hotkey uses the Carbon Event Manager, not a `CGEventTap`, so it needs no Accessibility permission either.
  - No network, camera, or microphone use anywhere in the source.
  Entitlements match actual behavior — no gaps, no unused grants.
- **Dead code / unused files**: none in `Sources/`. There is an empty, untracked `docs/` directory at the repo root (no files in it, nothing under git); harmless but can be deleted if not in use.
- **Version currency**: `Info.plist` (embedded in `build.sh`) reports `CFBundleShortVersionString = 1.0`, `CFBundleVersion = 1`. The DMG in the repo root is `SnapText-1.0.dmg`. These agree. No git tags exist in this repo, so there's no tag/version drift to reconcile.
- **Minor doc drift (not fixed, flagged for awareness)**: `README.md`'s Build section says `build.sh` "ad-hoc codesigns" the app; in practice `build.sh` now signs with the real Developer ID Application identity when one is present in the keychain, falling back to ad-hoc only when it isn't. Worth a one-line README update in a docs pass, not a functional bug.

## Fixes made
None required — build was already clean (no warnings/errors), no force-unwrap bugs, no TODOs/FIXMEs, entitlements already match actual usage.

## Open issues
- No automated test coverage exists for this app (menu bar / Vision OCR flow would need light integration or manual QA rather than unit tests, given it drives system UI and the Vision framework).
- README's signing description is slightly stale relative to `build.sh`'s actual Developer-ID-first signing logic (see above).
- Empty `docs/` directory at repo root — not tracked by git, likely a leftover local scratch folder; safe to remove.

## Current version
**1.0** (build 1) — matches `SnapText-1.0.dmg` in the repo root. No git tags cut yet.
