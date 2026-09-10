import SwiftUI

/// Same visual/interaction pattern as MacGroom's
/// `Sources/Views/LicenseManagementView.swift`: status card, verification
/// banner, Enter/Update License button — scoped to MacPeel's own
/// `@AppStorage` key and `MacPeelLicenseChecker`.
struct LicenseManagementView: View {
    @AppStorage("com.rajeshsood.macpeel.licenseKey") private var storedLicenseKey = ""

    // Settings is its own Scene/window — it doesn't inherit the main
    // app's environment, so this view verifies independently.
    private let checker = MacPeelLicenseChecker()

    @State private var isLicenseActive = false
    @State private var showLicenseEntry = false
    @State private var verificationMessage = ""
    @State private var verificationError = false
    @State private var isVerifying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if isVerifying {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.appAccent)
                } else {
                    Image(systemName: isLicenseActive ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isLicenseActive ? Color.appAccent : .gray)
                        .font(.system(size: 18))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isLicenseActive)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("MacPeel Pro")
                        .appFont(.headline)
                    Text(isVerifying ? "Verifying…" : (isLicenseActive ? "License Active" : "Free Version"))
                        .appFont(.caption, weight: .regular)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if !isLicenseActive {
                    Text("\(UsageTracker.remainingToday)/\(UsageTracker.freeDailyLimit) today")
                        .appFont(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .cardStyle(padding: 12)

            if !verificationMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: verificationError ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundColor(verificationError ? .red : .green)
                    Text(verificationMessage)
                        .appFont(.caption)
                }
                .padding(10)
                .background((verificationError ? Color.red : Color.green).opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 8) {
                Button(action: { showLicenseEntry = true }) {
                    Text(storedLicenseKey.isEmpty ? "Enter License Key" : "Update License")
                        .appFont(.body)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.appAccent)

                if !storedLicenseKey.isEmpty {
                    Button(action: clearLicense) {
                        Image(systemName: "xmark.circle")
                            .appFont(.body)
                    }
                    .buttonStyle(.bordered)
                    .help("Remove stored license key")
                }

                Spacer()

                Button("Unlock Pro…") {
                    NSWorkspace.shared.open(MacPeelLicenseConfig.purchaseURL)
                }
                .buttonStyle(.link)
                .appFont(.caption)
            }

            if !isLicenseActive {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Unlimited daily OCR (free is capped at \(UsageTracker.freeDailyLimit)/day)", systemImage: "infinity")
                    Label("Batch OCR — select multiple images at once", systemImage: "square.stack")
                    Label("OCR history log, copyable", systemImage: "clock.arrow.circlepath")
                    Label("Custom hotkey remapping", systemImage: "keyboard")
                }
                .appFont(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showLicenseEntry) {
            LicenseEntrySheet(isPresented: $showLicenseEntry, onLicenseEntered: handleLicenseEntry)
        }
        .task(id: storedLicenseKey) {
            guard !storedLicenseKey.isEmpty else {
                isLicenseActive = false
                return
            }
            await verify(storedLicenseKey)
        }
    }

    private func handleLicenseEntry(_ key: String) {
        storedLicenseKey = key
        showLicenseEntry = false
    }

    private func verify(_ key: String) async {
        isVerifying = true
        verificationMessage = ""
        defer { isVerifying = false }

        do {
            let license = try await checker.verify(licenseKey: key)
            isLicenseActive = license.isValid
            verificationMessage = "License verified — MacPeel Pro unlocked."
            verificationError = false
        } catch {
            isLicenseActive = false
            verificationMessage = (error as? MacPeelLicenseError)?.errorDescription ?? "License verification failed."
            verificationError = true
        }
    }

    private func clearLicense() {
        checker.clearCache(storedLicenseKey)
        storedLicenseKey = ""
        isLicenseActive = false
        verificationMessage = "License key removed"
        verificationError = false
    }
}

struct LicenseEntrySheet: View {
    @Binding var isPresented: Bool
    var onLicenseEntered: (String) -> Void

    @State private var licenseKey = ""
    @State private var errorMessage = ""
    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enter License Key")
                    .appFont(.title3)
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Paste your license key from the email you received after purchase:")
                    .appFont(.body)
                    .foregroundStyle(.secondary)

                TextEditor(text: $licenseKey)
                    // `.appFont` has no `TextEditor` overload, so the scale
                    // is applied directly here — this is the one place a
                    // user reads/verifies a pasted license key, and it
                    // previously didn't grow with Settings' Text Size
                    // while every other label in this sheet did.
                    .font(.system(size: AppFontStyle.body.basePointSize * textScale, design: .monospaced))
                    .frame(height: 100)
                    .padding(8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            }

            if !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundColor(.red)
                    Text(errorMessage)
                        .appFont(.caption)
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .cornerRadius(6)
            }

            HStack(spacing: 12) {
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save License") { saveLicense() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.appAccent)
                    .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 450, height: 320)
    }

    private func saveLicense() {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            errorMessage = "License key cannot be empty"
            return
        }
        let validCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        guard trimmedKey.unicodeScalars.allSatisfy({ validCharacters.contains($0) }) else {
            errorMessage = "License key contains invalid characters"
            return
        }
        onLicenseEntered(trimmedKey)
        isPresented = false
    }
}
