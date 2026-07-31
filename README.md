# SnapText

A lightweight macOS screenshot-to-text menu bar app, written in Swift/AppKit
with no third-party dependencies. Offline and private — OCR runs entirely
on-device via Apple's Vision framework; nothing leaves your Mac.

## Features

- **⌘⇧O** (or the menu) opens macOS's own region-selection crosshair —
  the same UI as ⌘⇧4 — then runs on-device text recognition on the capture
  and copies the result straight to the clipboard
- **Choose Image…** runs the same OCR on an existing image file (PNG, JPG,
  etc.) via a standard file picker, for text in screenshots or photos you
  already have saved rather than a fresh screen capture
- Menu bar icon flashes ✓ on success, **?** if no text was found; reverts
  after ~1s. No windows, no popups to dismiss
- Esc during selection cancels cleanly — nothing is copied, nothing is left
  on disk (the capture is a temp file, deleted immediately after OCR)
- No Dock icon (`LSUIElement`), minimal footprint

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/soodrajesh/mac-ocr.git
cd mac-ocr
./build.sh
open /Applications/SnapText.app
```

`build.sh` compiles `Sources/*.swift`, assembles `SnapText.app`, ad-hoc
codesigns it (`codesign --sign -`), and installs it to `/Applications`.

## Permissions

The first capture will prompt for **Screen Recording** access (macOS
attributes this to whichever app invokes `screencapture`, even as a
subprocess). Grant it in:

**System Settings → Privacy & Security → Screen Recording → enable SnapText**

If it stops prompting/working after a rebuild, toggle the checkbox off and
back on — macOS keys the grant to the app's code signature, which changes
each time an ad-hoc-signed binary is rebuilt.

## Auto-start at login

System Settings → General → Login Items & Extensions → **+** → select
`SnapText.app`.

## Notes

- Recognition uses Vision's `.accurate` mode with language correction —
  slower than `.fast` but noticeably better on screenshots of UI text, code,
  and mixed fonts.
- The ⌘⇧O shortcut is registered globally via Carbon's Event Manager — if
  another app already claims that combination, SnapText's registration will
  silently fail to bind.
- Pairs well with [ClipKeep](https://github.com/soodrajesh/mac-clipboard):
  since SnapText's clipboard writes look like any other copy, they show up
  in ClipKeep's history automatically.

## License

MIT
