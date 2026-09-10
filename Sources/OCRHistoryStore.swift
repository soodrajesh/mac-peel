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

/// Keeps the most recent OCR results in `UserDefaults` (plain text, not
/// sensitive credential-grade data — Keychain would be overkill here, and
/// this needs to be freely readable/clearable from Settings). Capped so
/// the stored blob can't grow unbounded across a long-running install.
enum OCRHistoryStore {
    static let maxEntries = 50
    private static let key = "com.rajeshsood.snaptext.ocrHistory"

    static func all() -> [OCRHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
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

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func save(_ entries: [OCRHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
