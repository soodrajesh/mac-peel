# MacPeel

A lightweight macOS screenshot-to-text menu bar app, written in Swift/
AppKit + SwiftUI with no third-party dependencies. Offline and private —
OCR runs entirely on-device via Apple's Vision framework; nothing leaves
your Mac.

The Settings window recently got a visual refresh — tinted purple icon
tiles, card-based sections, a prominent daily-usage progress bar, and an
audited light mode — following the shared mac-apps "modern & colorful"
design system. See `CHANGELOG.md`.

## Features

- **⌘⇧O** (or the menu) opens macOS's own region-selection crosshair —
  the same UI as ⌘⇧4 — then runs on-device text recognition on the capture
  and copies the result straight to the clipboard
- **Choose Image…** runs the same OCR on an existing image file (PNG, JPG,
  etc.) via a standard file picker, for text in screenshots or photos you
  already have saved rather than a fresh screen capture
- A **Settings window** (menu → Settings…, or ⌘,) for Appearance
  (System/Light/Dark), Text Size, the capture shortcut, daily usage, OCR
  history, and license management — see below
- Menu bar icon flashes ✓ on success, **?** if no text was found, or a
  lock icon if the free daily limit is reached; reverts after ~1s. No
  windows, no popups to dismiss for an ordinary capture
- Esc during selection cancels cleanly — nothing is copied, nothing is left
  on disk (the capture is a temp file, deleted immediately after OCR)
- No Dock icon (`LSUIElement`), minimal footprint

## Free vs. MacPeel Pro

MacPeel is free to use, with a fair daily cap; **MacPeel Pro** removes it
and adds power-user features. Both tiers run the same on-device OCR —
nothing about recognition quality changes with the license.

| | Free | Pro |
|---|---|---|
| Region-capture OCR | ✓ | ✓ |
| Choose Image OCR | ✓ | ✓ |
| Daily OCR operations | 20/day (resets at local midnight) | Unlimited |
| Batch OCR (select multiple images at once) | – | ✓ |
| OCR history log (recent results, copyable) | – | ✓ |
| Custom hotkey remapping | – | ✓ (default stays ⌘⇧O) |

When the free cap is hit, MacPeel shows a clear "Unlock Pro" notification
(and flashes a lock icon) instead of silently failing the capture.

### MacPeel Pro licensing

Pro is unlocked with a license key, entered in **Settings → License**. It's
verified against [Polar.sh](https://polar.sh)'s customer-portal License
Keys API — the same integration pattern as MacGroom's, but a **separate**
Polar organization/product from MacGroom's own Suite Pro license. Verified
license state is cached in the Keychain for 7 days so Pro features keep
working offline between checks.

The Polar organization/product for MacPeel Pro doesn't exist yet — see the
`TODO(polar)` block at the top of `Sources/License/MacPeelLicense.swift`
for exactly what needs to be created and filled in before this goes live.

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/soodrajesh/mac-peel.git
cd mac-peel
./build.sh
open /Applications/MacPeel.app
```

`build.sh` compiles `Sources/*.swift`, assembles `MacPeel.app`, ad-hoc
codesigns it (`codesign --sign -`), and installs it to `/Applications`.

## Permissions

The first capture will prompt for **Screen Recording** access (macOS
attributes this to whichever app invokes `screencapture`, even as a
subprocess). Grant it in:

**System Settings → Privacy & Security → Screen Recording → enable MacPeel**

If it stops prompting/working after a rebuild, toggle the checkbox off and
back on — macOS keys the grant to the app's code signature, which changes
each time an ad-hoc-signed binary is rebuilt.

## Auto-start at login

System Settings → General → Login Items & Extensions → **+** → select
`MacPeel.app`.

## Notes

- Recognition uses Vision's `.accurate` mode with language correction —
  slower than `.fast` but noticeably better on screenshots of UI text, code,
  and mixed fonts.
- The capture shortcut (⌘⇧O by default, remappable in Settings for Pro) is
  registered globally via Carbon's Event Manager — if another app already
  claims that combination, MacPeel's registration will
  silently fail to bind.
- Pairs well with [ClipKeep](https://github.com/soodrajesh/mac-clipboard):
  since MacPeel's clipboard writes look like any other copy, they show up
  in ClipKeep's history automatically.

## License

MIT
