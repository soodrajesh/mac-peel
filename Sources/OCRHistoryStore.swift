import Foundation

/// One past OCR result — Pro-only feature, so recent extracted text stays
/// available to re-copy without redoing the capture.
struct OCRHistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
    let source: Source

    enum Source: String, Codable {
        case regionCapture
        case chooseImage

        var label: String {
            switch self {
            case .regionCapture: return "Region Capture"
            case .chooseImage: return "Choose Image"
            }
        }
    }
}

/// Keeps the most recent OCR results on disk, in the app's own Application
/// Support directory — *not* `UserDefaults`. SnapText ships unsandboxed
/// (see `SnapText.entitlements`), and a `UserDefaults`-backed plist is
/// trivially world-readable by any other local process via
/// `defaults read com.rajeshsood.snaptext com.rajeshsood.snaptext.ocrHistory`,
/// no permission prompt required. Extracted OCR text routinely includes
/// passwords, 2FA codes, and other sensitive material — that exposure was
/// unacceptable for a feature whose entire point is "keep recent results
/// around."
///
/// The file lives at `~/Library/Application Support/SnapText/history.json`
/// with POSIX mode `0600` (owner read/write only), reasserted after every
/// write since `FileManager` doesn't otherwise guarantee restrictive
/// permissions on file creation. This isn't Keychain-grade protection, but
/// it closes the "any local process can read it with zero privilege" hole,
/// which was the actual exploitable gap; the data volume here (up to 50
/// free-form text entries, potentially several KB each) is also a poor fit
/// for Keychain's per-item size ceiling.
enum OCRHistoryStore {
    static let maxEntries = 50

    private static let directoryName = "SnapText"
    private static let fileName = "history.json"

    private static var storeURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent(directoryName).appendingPathComponent(fileName)
    }

    static func all() -> [OCRHistoryEntry] {
        guard let url = storeURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([OCRHistoryEntry].self, from: data)) ?? []
    }

    /// Records a new result at the front, trimmed to `maxEntries`. No-op
    /// when text is empty — a failed/empty recognition isn't worth logging.
    static func record(text: String, source: OCRHistoryEntry.Source) {
        guard !text.isEmpty else { return }
        var entries = all()
        entries.insert(OCRHistoryEntry(id: UUID(), date: Date(), text: text, source: source), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save(entries)
    }

    /// Deletes a single entry — lets a user remove one sensitive capture
    /// without clearing the entire log.
    static func delete(id: UUID) {
        var entries = all()
        entries.removeAll { $0.id == id }
        save(entries)
    }

    static func clear() {
        guard let url = storeURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func save(_ entries: [OCRHistoryEntry]) {
        guard let url = storeURL, let data = try? JSONEncoder().encode(entries) else { return }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: url, options: .atomic)
            // Reassert restrictive permissions explicitly: atomic writes go
            // through a temp file + replace, which doesn't reliably inherit
            // the directory's mode, and a future FileManager/OS change
            // shouldn't be able to silently widen this.
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            // Best-effort: nothing more useful to do than leave the
            // previous on-disk state untouched.
        }
    }
}
