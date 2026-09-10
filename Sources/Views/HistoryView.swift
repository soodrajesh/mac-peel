import SwiftUI
import AppKit

/// Pro-only OCR history log: the most recent extracted-text results,
/// each copyable back to the clipboard on demand.
struct HistoryView: View {
    let isProLicensed: Bool

    @State private var entries: [OCRHistoryEntry] = OCRHistoryStore.all()
    @State private var copiedID: UUID?
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent OCR results are kept here so you can re-copy text without redoing the capture.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !entries.isEmpty {
                    Button("Clear", role: .destructive) {
                        showClearConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .appFont(.caption)
                }
            }
            .confirmationDialog(
                "Clear all \(entries.count) OCR history entries? This can't be undone.",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    OCRHistoryStore.clear()
                    entries = []
                }
                Button("Cancel", role: .cancel) {}
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
        .contextMenu {
            Button(role: .destructive) {
                OCRHistoryStore.delete(id: entry.id)
                entries.removeAll { $0.id == entry.id }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
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
            Text("\(feature) is a MacPeel Pro feature.")
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(6)
    }
}
