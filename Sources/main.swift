import AppKit
import Carbon.HIToolbox
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var isCapturing = false

    private let idleSymbol = "text.viewfinder"
    private let successSymbol = "checkmark.circle.fill"
    private let emptySymbol = "questionmark.circle"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: idleSymbol, accessibilityDescription: "SnapText")

        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture Region & OCR", action: #selector(capture), keyEquivalent: "o")
        captureItem.keyEquivalentModifierMask = [.command, .shift]
        captureItem.target = self
        menu.addItem(captureItem)
        let openImageItem = NSMenuItem(title: "Choose Image…", action: #selector(chooseImage), keyEquivalent: "")
        openImageItem.target = self
        menu.addItem(openImageItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit SnapText", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        // kVK_ANSI_O = 31; cmdKey|shiftKey are Carbon modifier masks for ⌘⇧.
        hotKey = HotKey(keyCode: 31, modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            self?.capture()
        }
    }

    @objc private func capture() {
        guard !isCapturing else { return }
        isCapturing = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let image = ScreenCapture.captureRegion() else {
                DispatchQueue.main.async { self?.isCapturing = false } // user pressed Esc
                return
            }
            self?.runOCR(on: image)
        }
    }

    @objc private func chooseImage() {
        guard !isCapturing else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) else { return }

        isCapturing = true
        runOCR(on: image)
    }

    /// Shared tail end of both entry points: hash out to a background queue
    /// so Vision's `.accurate` pass never blocks the main thread, then hop
    /// back to update the icon.
    private func runOCR(on image: NSImage) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = OCRService.recognize(image)
            DispatchQueue.main.async {
                self?.finish(text: text)
            }
        }
    }

    private func finish(text: String) {
        isCapturing = false
        guard !text.isEmpty else {
            flash(symbol: emptySymbol)
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
