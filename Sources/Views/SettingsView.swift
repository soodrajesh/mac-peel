import SwiftUI

/// MacPeel's Settings window. Order follows the shared mac-apps design
/// system: Appearance, Text Size, app-specific preferences (Shortcut,
/// Batch OCR toggle), History, License, About.
struct SettingsView: View {
    @AppStorage("com.rajeshsood.macpeel.appearance") private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage("com.rajeshsood.macpeel.textSize") private var textSizeRaw = TextSizePreference.medium.rawValue
    @AppStorage("com.rajeshsood.macpeel.licenseKey") private var storedLicenseKey = ""
    @AppStorage("com.rajeshsood.macpeel.copyNotifications") private var copyNotificationsEnabled = true

    @State private var isProLicensed = false
    @State private var isCheckingLicense = true
    @State private var section: SettingsSection? = .general

    // Independent verification — Settings doesn't inherit the main app's
    // environment (see DESIGN-SYSTEM.md's note on Settings panes).
    private let checker = MacPeelLicenseChecker()

    @State private var hotKeyCode: UInt32 = HotKeyPreference.keyCode
    @State private var hotKeyModifiers: UInt32 = HotKeyPreference.modifiers

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .system
    }

    private var textSize: TextSizePreference {
        TextSizePreference(rawValue: textSizeRaw) ?? .medium
    }

    @ObservedObject private var updateState = UpdateState.shared

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general = "General"
        case history = "History"
        case license = "License"
        case updates = "Updates"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .history: return "clock.arrow.circlepath"
            case .license: return "key"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $section) { item in
                HStack(spacing: 10) {
                    IconTile(systemName: item.icon)
                    Text(item.rawValue)
                        .appFont(.body)
                }
                .tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            .background(.regularMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch section ?? .general {
                    case .general: generalSection
                    case .history: HistoryView(isProLicensed: isProLicensed)
                    case .license: LicenseManagementView()
                    case .updates: updatesSection
                    case .about: aboutSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: section)
            }
            .background(Color(.windowBackgroundColor))
        }
        .frame(width: 560, height: 420)
        .environment(\.textScale, textSize.scale)
        .preferredColorScheme(appearance.colorScheme)
        .task(id: storedLicenseKey) {
            await refreshLicense()
        }
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsGroup("Appearance") {
                Picker("", selection: $appearanceRaw) {
                    ForEach(AppearancePreference.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingsGroup("Text Size") {
                Picker("", selection: $textSizeRaw) {
                    ForEach(TextSizePreference.allCases) { option in
                        Text(option.label).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            settingsGroup("Capture Shortcut") {
                if isProLicensed {
                    ShortcutRecorderView(keyCode: $hotKeyCode, modifiers: $hotKeyModifiers) { code, mods in
                        HotKeyPreference.set(keyCode: code, modifiers: mods)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(HotKeyPreference.displayString(keyCode: HotKeyPreference.defaultKeyCode, modifiers: HotKeyPreference.defaultModifiers))
                            .appFont(.body, weight: .medium)
                            .monospaced()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                        Spacer()
                    }
                    ProLockedNotice(feature: "Custom hotkey remapping")
                }
            }

            settingsGroup("Daily Usage") {
                if isProLicensed {
                    HStack(spacing: 10) {
                        IconTile(systemName: "infinity", size: 22)
                        Text("Unlimited (MacPeel Pro)")
                            .appFont(.body, weight: .semibold)
                            .foregroundStyle(Color.appAccent)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(UsageTracker.countToday)")
                                .appFont(.title, weight: .bold)
                                .foregroundStyle(Color.appAccent)
                            Text("of \(UsageTracker.freeDailyLimit) free OCR operations used today")
                                .appFont(.body, weight: .semibold)
                        }
                        ProgressView(value: Double(UsageTracker.countToday), total: Double(UsageTracker.freeDailyLimit))
                            .tint(Color.appAccent)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: UsageTracker.countToday)
                        Text("Resets at midnight. Region capture and Choose Image both count.")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            settingsGroup("Copy Confirmation") {
                Toggle("Show a notification with a text preview after each copy", isOn: $copyNotificationsEnabled)
                    .appFont(.body)
                Text("Off, or if notifications aren't authorized, MacPeel still confirms with a quick menu bar icon flash.")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }

            settingsGroup("Batch OCR") {
                if isProLicensed {
                    HStack(spacing: 10) {
                        IconTile(systemName: "checkmark.circle.fill", size: 22)
                        Text("Choose Image… allows selecting multiple images at once.")
                            .appFont(.body)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ProLockedNotice(feature: "Batch OCR (select multiple images at once)")
                }
            }
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            settingsGroup("Software Update") {
                if let update = updateState.availableUpdate {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MacPeel \(update.version) is available (you have \(appVersion))")
                            .appFont(.body)
                        if let notes = update.notes, !notes.isEmpty {
                            Text(notes)
                                .appFont(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Get It") {
                            guard let url = URL(string: update.url) else { return }
                            NSWorkspace.shared.open(url)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                    }
                } else {
                    Text("You're on the latest version (\(appVersion)).")
                        .appFont(.body)
                        .foregroundStyle(.secondary)
                }

                Button("Check for Updates") { updateState.checkForUpdates() }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Intentional exception to the `.appFont` policy: this is a
                // decorative glyph, not text a user reads, so it stays a
                // fixed size rather than scaling with Text Size.
                IconTile(systemName: "text.viewfinder", size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("MacPeel")
                        .appFont(.title2, weight: .semibold)
                    Text("Version \(appVersion) (\(appBuild))")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("A lightweight, offline screenshot-to-text menu bar app. OCR runs entirely on-device via Apple's Vision framework — nothing leaves your Mac.")
                .appFont(.body)
                .foregroundStyle(.secondary)

            Text("© 2026 Rajesh Sood")
                .appFont(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .cardStyle()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    @ViewBuilder
    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appFont(.subheadline, weight: .semibold)
                .foregroundStyle(.secondary)
            content()
        }
        .cardStyle()
    }

    private func refreshLicense() async {
        isCheckingLicense = true
        defer { isCheckingLicense = false }
        guard !storedLicenseKey.isEmpty else {
            isProLicensed = false
            return
        }
        do {
            let license = try await checker.verify(licenseKey: storedLicenseKey)
            isProLicensed = license.isValid
        } catch {
            isProLicensed = false
        }
    }
}
