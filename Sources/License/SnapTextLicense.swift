import Foundation
import Security

// MARK: - Polar.sh integration config
//
// SnapText Pro is a SEPARATE Polar.sh organization/product from MacGroom's
// — its own store, not a shared Suite Pro license. Nothing below is
// provisioned yet; this is the integration point, clearly marked, so
// wiring up the real product later is a config-only change. Modeled on
// `mac-cleanup/Sources/MacGroomLicenseCheck.swift`'s `LicenseChecker`,
// which validates against Polar's customer-portal License Keys API
// (`POST /v1/customer-portal/license-keys/validate`) — a public endpoint,
// keyed by the license key + organization id, no API secret embedded in
// the binary.
//
// TODO(polar): before shipping SnapText Pro,
//   1. Create a Polar.sh organization + "SnapText Pro" product/benefit
//      with a License Keys benefit attached (polar.sh dashboard → Products
//      → New → Benefits → License Keys).
//   2. Copy the resulting organization ID into
//      `SnapTextLicenseConfig.organizationID` below (or set the
//      SNAPTEXT_POLAR_ORG_ID env var at build time).
//   3. Set the checkout URL used by the "Unlock Pro" upsell
//      (`SnapTextLicenseConfig.purchaseURL`) to the real product's
//      checkout link once it exists.
//   4. No Polar API key/secret is needed in this binary — the
//      customer-portal validate endpoint is deliberately public/client-safe
//      (confirmed for MacGroom's own integration: an unauthenticated
//      request with a well-formed body returns 404 for an unknown key, not
//      401/403).
enum SnapTextLicenseConfig {
    /// TODO(polar): fill in once the SnapText Pro organization/product
    /// exists. Left empty so `LicenseChecker` can refuse to trust any key
    /// until this is configured, rather than silently validating against
    /// an organization id of "".
    static let organizationID: String = {
        ProcessInfo.processInfo.environment["SNAPTEXT_POLAR_ORG_ID"] ?? ""
    }()

    /// TODO(polar): point this at the real checkout URL once the product
    /// page exists on gogenops.com / the Polar storefront.
    static let purchaseURL = URL(string: "https://gogenops.com/snaptext-pro")!

    static var isConfigured: Bool { !organizationID.isEmpty }
}

/// Represents a verified SnapText Pro license.
struct SnapTextLicense: Codable, Equatable {
    let key: String
    let isValid: Bool
    let status: String?
    let expiresAt: Date?
    let activationLimit: Int?
    let activationUsage: Int?
}

enum SnapTextLicenseError: LocalizedError {
    case notConfigured
    case invalidLicenseKey
    case networkError(URLError)
    case invalidResponse
    case licenseExpired
    case licenseDisabled
    case activationLimitExceeded
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SnapText Pro isn't configured yet — check back soon."
        case .invalidLicenseKey:
            return "The license key is invalid or not recognized."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Received an invalid response from the license server."
        case .licenseExpired:
            return "This license has expired."
        case .licenseDisabled:
            return "This license has been disabled."
        case .activationLimitExceeded:
            return "This license has reached its activation limit."
        case .unknown(let message):
            return message
        }
    }
}

/// Local cache for verified license state, in the Keychain rather than
/// `UserDefaults` so a license can't be forged with a single
/// `defaults write`. Mirrors the intent of `mac-cleanup`'s
/// `SecureLicenseCache`, scoped to SnapText's own bundle id; skips its
/// HMAC tamper tag since that key would itself need to be masked into this
/// much smaller binary for comparatively low benefit — the honest ceiling
/// either way is "extract a secret from the shipped binary," not "forge a
/// cache entry via `defaults write`," which the Keychain move alone closes.
private enum SnapTextLicenseCache {
    private static let service = "com.rajeshsood.snaptext.license.cache.v1"

    private struct CachedEnvelope: Codable {
        let cachedAt: Date
        let license: SnapTextLicense
    }

    static func read(_ licenseKey: String) -> (Date, SnapTextLicense)? {
        guard let data = keychainRead(account: licenseKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(CachedEnvelope.self, from: data) else { return nil }
        return (envelope.cachedAt, envelope.license)
    }

    static func write(_ licenseKey: String, _ license: SnapTextLicense) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(CachedEnvelope(cachedAt: Date(), license: license)) else { return }
        keychainWrite(account: licenseKey, data: data)
    }

    static func clear(_ licenseKey: String) {
        keychainDelete(account: licenseKey)
    }

    private static func keychainRead(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static func keychainWrite(account: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // Not tied to device-unlock state — SnapText can fire (e.g. from a
        // login item) before the user has unlocked their session.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Verifies a SnapText Pro license key against Polar.sh's customer-portal
/// License Keys API — same shape as `mac-cleanup`'s `LicenseChecker`, a
/// separate organization/product from MacGroom's. See
/// `SnapTextLicenseConfig` for the (currently unfilled) organization id
/// this validates against.
final class SnapTextLicenseChecker {
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    /// Verify a license key, using a 7-day Keychain cache so the app still
    /// unlocks Pro features offline between checks.
    func verify(licenseKey: String, useCache: Bool = true, cacheDuration: TimeInterval = 7 * 24 * 3600) async throws -> SnapTextLicense {
        guard SnapTextLicenseConfig.isConfigured else { throw SnapTextLicenseError.notConfigured }
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if useCache, let cached = SnapTextLicenseCache.read(trimmedKey) {
            if Date().timeIntervalSince(cached.0) < cacheDuration {
                return cached.1
            }
            SnapTextLicenseCache.clear(trimmedKey)
        }

        let license = try await validateRemote(trimmedKey)
        SnapTextLicenseCache.write(trimmedKey, license)
        return license
    }

    func clearCache(_ licenseKey: String) {
        SnapTextLicenseCache.clear(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Remote call

    private struct PolarLicenseKeyResponse: Decodable {
        let key: String
        let status: String
        let limitActivations: Int?
        let usage: Int?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case key, status, usage
            case limitActivations = "limit_activations"
            case expiresAt = "expires_at"
        }
    }

    private func validateRemote(_ licenseKey: String) async throws -> SnapTextLicense {
        var request = URLRequest(url: URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/validate")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "key": licenseKey,
            "organization_id": SnapTextLicenseConfig.organizationID
        ])

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await urlSession.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw SnapTextLicenseError.invalidResponse }
            data = responseData
            http = httpResponse
        } catch let error as URLError {
            throw SnapTextLicenseError.networkError(error)
        }

        guard http.statusCode == 200 else {
            throw mapErrorResponse(status: http.statusCode, data: data)
        }

        guard let response = try? JSONDecoder().decode(PolarLicenseKeyResponse.self, from: data) else {
            throw SnapTextLicenseError.invalidResponse
        }

        // A 200 from /validate means the key checked out against this
        // organization — `status` is informational here, not a second
        // gate, since Polar already returns a non-200 (mapped below) for
        // revoked/disabled keys.
        return SnapTextLicense(
            key: response.key,
            isValid: true,
            status: response.status,
            expiresAt: response.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            activationLimit: response.limitActivations,
            activationUsage: response.usage
        )
    }

    /// Polar's error responses come in two shapes: a `404` with
    /// `{"error": "ResourceNotFound", "detail": "Not found"}` for a key
    /// that doesn't exist under this organization, and a `422` with
    /// `{"detail": [{"msg": "...", "loc": [...]}]}` for a malformed
    /// request.
    private func mapErrorResponse(status: Int, data: Data) -> SnapTextLicenseError {
        let message = errorMessage(from: data)
        switch status {
        case 404:
            return .invalidLicenseKey
        case 403, 401:
            return .licenseDisabled
        default:
            if let message {
                let lower = message.lowercased()
                if lower.contains("expired") { return .licenseExpired }
                if lower.contains("disabled") || lower.contains("revoked") { return .licenseDisabled }
                if lower.contains("activation limit") || lower.contains("usage limit") { return .activationLimitExceeded }
            }
            return .unknown(message ?? "License check failed (HTTP \(status)).")
        }
    }

    private func errorMessage(from data: Data) -> String? {
        struct FlatError: Decodable { let error: String?; let detail: String? }
        struct ValidationDetail: Decodable { let msg: String }
        struct ValidationError: Decodable { let detail: [ValidationDetail] }

        if let flat = try? JSONDecoder().decode(FlatError.self, from: data) {
            return flat.detail ?? flat.error
        }
        if let validation = try? JSONDecoder().decode(ValidationError.self, from: data) {
            return validation.detail.map(\.msg).joined(separator: "; ")
        }
        return String(data: data, encoding: .utf8)
    }
}
