import AppKit

enum ScreenCapture {
    /// The three distinguishable outcomes of a region capture. Previously
    /// this collapsed to a single `NSImage?`, which made a denied Screen
    /// Recording permission indistinguishable from the user simply pressing
    /// Esc — both silently returned `nil` and produced zero UI feedback.
    enum CaptureOutcome {
        case success(NSImage)
        /// The user pressed Esc to dismiss the selection UI. Silent by
        /// design — this is the expected, common case.
        case cancelled
        /// `screencapture` failed to produce a file for a reason other than
        /// a clean user cancel — almost always a Screen Recording
        /// permission problem. Worth surfacing distinctly.
        case permissionDenied
    }

    /// Runs macOS's own interactive region-selection UI — the same crosshair
    /// as ⌘⇧4 — and reports what happened, or `.cancelled` if the user
    /// pressed Esc. Shelling out to `/usr/sbin/screencapture` reuses
    /// Apple's selection UI and Screen Recording permission handling instead
    /// of reimplementing either.
    static func captureRegion() -> CaptureOutcome {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snaptext-\(UUID().uuidString).png")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-t", "png", tmp.path]

        let stderrPipe = Pipe()
        task.standardError = stderrPipe

        do { try task.run() } catch { return .permissionDenied }
        task.waitUntilExit()

        defer { try? FileManager.default.removeItem(at: tmp) }

        // screencapture writes nothing at all if the user cancels the
        // selection — that's the common, silent-by-design case.
        if FileManager.default.fileExists(atPath: tmp.path), let image = NSImage(contentsOf: tmp) {
            return .success(image)
        }

        // No file was written. A plain Esc cancel exits 0 with nothing on
        // stderr; a Screen Recording permission failure reliably differs
        // from that — either a non-zero exit status or diagnostic output on
        // stderr. This isn't officially documented `screencapture` API, but
        // it's the only signal available while still delegating capture (and
        // its permission handling) to Apple's own binary rather than
        // reimplementing it with CGWindowListCreateImage/SCScreenshotManager.
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let looksLikeCleanCancel = task.terminationStatus == 0 && stderrText.isEmpty
        return looksLikeCleanCancel ? .cancelled : .permissionDenied
    }
}
