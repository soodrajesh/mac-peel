import Foundation
import SwiftUI

/// The manifest MacPeel polls to learn a newer version exists. Same shape
/// and endpoint as MacGroom's `UpdateCheckService.swift` — the poll goes
/// through `/api/update-check` (not a direct manifest fetch) so gogenops.com
/// has a record of what versions are actually still installed and running.
/// MacPeel's manifest lives at gogenops.com/mac-apps/macpeel/updates.json
/// and is served through that same endpoint.
struct UpdateManifest: Codable, Equatable {
    let version: String
    let notes: String?
    let url: String
}

/// Lightweight, safe update *checking* — deliberately not silent
/// auto-update. Compares the hosted manifest's version against this
/// build's own `CFBundleShortVersionString` and, if newer, hands back the
/// manifest for the UI to show a "vX is available" prompt linking out to
/// wherever `url` points. Doesn't download or replace the running app
/// bundle itself — see MacGroom's `UpdateCheckService.swift` doc comment
/// for why (no signature-verification story yet for silent self-replacement).
enum UpdateCheckService {
    static func checkForUpdate() async -> UpdateManifest? {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

        var components = URLComponents(string: "https://gogenops.com/api/update-check")!
        components.queryItems = [
            URLQueryItem(name: "app", value: "macpeel"),
            URLQueryItem(name: "v", value: currentVersion),
            URLQueryItem(name: "os", value: macOSVersionString()),
        ]

        guard let url = components.url,
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let manifest = try? JSONDecoder().decode(UpdateManifest.self, from: data) else { return nil }

        return isNewer(manifest.version, than: currentVersion) ? manifest : nil
    }

    private static func macOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// Component-wise numeric comparison ("1.10" > "1.9"), not a string
    /// compare (which would get that backwards) — pads the shorter side
    /// with zeros so "1.2" vs "1.2.1" compares correctly too.
    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}

/// Holds the launch-time update-check result so the Settings window's
/// Updates section can read it back. MacPeel has no SwiftUI App/Scene
/// lifecycle (it's a plain `NSApplicationDelegate` menu-bar app — see
/// `SettingsWindowController`'s doc comment), so there's no shared
/// `@EnvironmentObject` to thread this through; this small singleton is the
/// bridge between `AppDelegate.applicationDidFinishLaunching` (which sets
/// it once, at launch) and `SettingsView` (which observes it and offers a
/// "Check for Updates" button to refresh it on demand).
@MainActor
final class UpdateState: ObservableObject {
    static let shared = UpdateState()

    @Published var availableUpdate: UpdateManifest?

    private init() {}

    /// Safe to call repeatedly (launch, and again from the Updates button) —
    /// each call simply replaces `availableUpdate`, including back to `nil`
    /// if a previously-flagged update is no longer newer than the running
    /// build. Silent either way; there's nothing meaningfully different to
    /// tell the user between those two cases.
    func checkForUpdates() {
        Task.detached(priority: .background) { [weak self] in
            let manifest = await UpdateCheckService.checkForUpdate()
            guard let self else { return }
            await MainActor.run { self.availableUpdate = manifest }
        }
    }
}
