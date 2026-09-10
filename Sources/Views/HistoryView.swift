import SwiftUI
import AppKit

/// Pro-only OCR history log: the most recent extracted-text results,
/// each copyable back to the clipboard on demand.
struct HistoryView: View {
    let isProLicensed: Bool

    @State private var entries: [OCRHistoryEntry] = OCRHistoryStore.all()
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent OCR results are kept here so you can re-copy text without redoing the capture.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !entries.isEmpty {
                    Button("Clear", role: .destructive) {
                        OCRHistoryStore.clear()
                        entries = []
                    }
                    .buttonStyle(.borderless)
                    .appFont(.caption)
                }
            }

            if !isProLicensed {
                ProLockedNotice(feature: "OCR history log")
            } else if entries.isEmpty {
                Text("No OCR results yet.")
                    .appFont(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(entries) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .onAppear { entries = OCRHistoryStore.all() }
    }

    private func historyRow(_ entry: OCRHistoryEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .appFont(.body)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(entry.source.label)
                    Text("·")
                    Text(entry.date.relativeDescription)
                }
                .appFont(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
                copiedID = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if copiedID == entry.id { copiedID = nil }
                }
            } label: {
                Image(systemName: copiedID == entry.id ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}

/// Small inline "this needs Pro" placeholder, reused by History and
/// Batch OCR sections in Settings.
struct ProLockedNotice: View {
    let feature: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text("\(feature) is a SnapText Pro feature.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}
