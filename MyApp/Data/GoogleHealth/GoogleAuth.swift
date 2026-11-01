import Foundation
import CryptoKit
import Security

/// Google OAuth 2.0 for a native iOS client: authorization code + PKCE, no client secret.
/// The UI opens `beginSignIn()` in a web authentication session and hands the callback URL to `completeSignIn`.
final class GoogleAuth {
    static let clientID = "5052986630-j4rtbk3d7ghdrrrh1svi3mcmdj94ks5n.apps.googleusercontent.com"
    /// Reversed client ID: the redirect scheme Google assigns to iOS OAuth clients.
    static let callbackScheme = "com.googleusercontent.apps.5052986630-j4rtbk3d7ghdrrrh1svi3mcmdj94ks5n"
    static let redirectURI = callbackScheme + ":/oauthredirect"
    static let scopes = ["activity_and_fitness", "health_metrics_and_measurements", "sleep", "profile"]
        .map { "https://www.googleapis.com/auth/googlehealth.\($0).readonly" }

    private struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiry: Date
    }

    private var tokens: Tokens? = Keychain.load()
    private var pending: (verifier: String, state: String)?

    var isSignedIn: Bool { tokens != nil }

    /// Consent-screen URL. Remembers the PKCE verifier and state for `completeSignIn`.
    func beginSignIn() -> URL {
        let verifier = Self.randomToken()
        let state = Self.randomToken()
        pending = (verifier, state)
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        return url.url!
    }

    func completeSignIn(callbackURL: URL) async throws {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard let pending, value("state") == pending.state else {
            throw HealthAPIError.signInFailed("The sign-in response didn’t match. Please try again.")
        }
        self.pending = nil
        if let error = value("error") {
            throw HealthAPIError.signInFailed(error == "access_denied" ? "Access to Google Health wasn’t granted." : error)
        }
        guard let code = value("code") else { throw HealthAPIError.signInFailed("Google didn’t return an authorization code.") }

        let response = try await tokenRequest([
            "code": code, "code_verifier": pending.verifier,
            "grant_type": "authorization_code", "redirect_uri": Self.redirectURI,
        ])
        guard let refreshToken = response.refresh_token else {
            throw HealthAPIError.signInFailed("Google didn’t return a refresh token.")
        }
        save(Tokens(accessToken: response.access_token, refreshToken: refreshToken, expiry: .now + response.expires_in))
    }

    /// A valid access token, refreshed when it is about to expire.
    /// A rejected refresh (e.g. the 7-day expiry for apps in Testing) signs the user out.
    func accessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens else { throw HealthAPIError.signedOut }
        if !forceRefresh, tokens.expiry > .now.addingTimeInterval(60) { return tokens.accessToken }
        do {
            let response = try await tokenRequest(["refresh_token": tokens.refreshToken, "grant_type": "refresh_token"])
            save(Tokens(accessToken: response.access_token, refreshToken: response.refresh_token ?? tokens.refreshToken,
                        expiry: .now + response.expires_in))
            return response.access_token
        } catch is URLError {
            throw HealthAPIError.offline
        } catch {
            signOut()
            throw HealthAPIError.sessionExpired
        }
    }

    func signOut() {
        tokens = nil
        Keychain.delete()
    }

    private func save(_ new: Tokens) {
        tokens = new
        Keychain.save(new)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Double
        let refresh_token: String?
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-._~"))
        request.httpBody = Data(fields.merging(["client_id": Self.clientID]) { current, _ in current }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let body = try? JSONDecoder().decode([String: String].self, from: data)
            throw HealthAPIError.signInFailed(body?["error_description"] ?? body?["error"] ?? "Google sign-in failed.")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private static func randomToken() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Stores the tokens as one Keychain item, available only on this device.
private enum Keychain {
    static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "GoogleHealth",
        kSecAttrAccount as String: "tokens",
    ]

    static func save<T: Encodable>(_ value: T) {
        delete()
        var item = query
        item[kSecValueData as String] = try? JSONEncoder().encode(value)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load<T: Decodable>() -> T? {
        var search = query
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

enum HealthAPIError: LocalizedError {
    case signedOut, sessionExpired, offline, accountNotLinked
    case signInFailed(String)
    case server(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .signedOut: "Connect Google Health to load your data."
        case .sessionExpired: "Your Google Health session expired. Connect again to keep syncing."
        case .offline: "You’re offline. Showing the last synced data."
        case .accountNotLinked: "Open the Google Health app once to link your account, then connect again."
        case .signInFailed(let message): message
        case .server(let status, let message): "Google Health error \(status): \(message)"
        }
    }
}
