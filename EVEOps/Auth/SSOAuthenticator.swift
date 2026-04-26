import Foundation
import AuthenticationServices
import CryptoKit

struct SSOTokenResponse: Codable, Sendable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case refreshToken = "refresh_token"
    }
}

struct SSOConfiguration: Sendable {
    let clientID: String
    let callbackURL: String
    let scopes: [String]

    static let `default` = SSOConfiguration(
        clientID: "27c5210c4d8a44538fdeeb7fc58f28b6",
        callbackURL: "eveauth-27c5210c4d8a44538fdeeb7fc58f28b6://callback",
        scopes: [
            "esi-location.read_location.v1",
            "esi-location.read_ship_type.v1",
            "esi-location.read_online.v1",
            "esi-skills.read_skills.v1",
            "esi-skills.read_skillqueue.v1",
            "esi-wallet.read_character_wallet.v1",
            "esi-assets.read_assets.v1",
            "esi-clones.read_clones.v1",
            "esi-clones.read_implants.v1",
            "esi-planets.manage_planets.v1",
            "esi-contracts.read_character_contracts.v1",
            "esi-industry.read_character_jobs.v1",
            "esi-mail.read_mail.v1",
            "esi-mail.send_mail.v1",
            "esi-mail.organize_mail.v1",
            "esi-fleets.read_fleet.v1",
            "esi-fleets.write_fleet.v1",
            "esi-characters.read_notifications.v1",
            "esi-corporations.read_structures.v1",
            "esi-corporations.read_corporation_membership.v1",
            "esi-industry.read_corporation_jobs.v1",
            "esi-assets.read_corporation_assets.v1",
            "esi-wallet.read_corporation_wallets.v1",
            "esi-contracts.read_corporation_contracts.v1",
            "esi-universe.read_structures.v1",
            "esi-characters.read_standings.v1",
            "esi-calendar.read_calendar_events.v1",
            "esi-calendar.respond_calendar_events.v1",
            "esi-fittings.read_fittings.v1",
            "esi-fittings.write_fittings.v1",
            "esi-killmails.read_killmails.v1",
            "esi-killmails.read_corporation_killmails.v1",
            "esi-markets.read_corporation_orders.v1",
            "esi-industry.read_corporation_mining.v1",
            "esi-characters.read_contacts.v1",
            "esi-characters.write_contacts.v1",
            "esi-ui.write_waypoint.v1",
            "esi-ui.open_window.v1",
            "esi-search.search_structures.v1",
            "esi-characters.read_agents_research.v1"
        ]
    )

    var scopeString: String { scopes.joined(separator: " ") }
}

@MainActor
final class SSOAuthenticator: NSObject {
    var isAuthenticating = false

    private let config: SSOConfiguration
    private var webAuthSession: ASWebAuthenticationSession?

    init(config: SSOConfiguration) {
        self.config = config
    }

    func authenticate() async throws -> SSOTokenResponse {
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        let state = UUID().uuidString

        var components = URLComponents(string: "https://login.eveonline.com/v2/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.callbackURL),
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "scope", value: config.scopeString),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]

        let authURL = components.url!

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            isAuthenticating = true
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "eveauth-\(config.clientID)"
            ) { url, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let url = url {
                    continuation.resume(returning: url)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webAuthSession = session
            session.start()
        }

        isAuthenticating = false

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw SSOError.invalidCallback
        }

        return try await exchangeCode(code, codeVerifier: codeVerifier)
    }

    func refreshToken(_ refreshToken: String) async throws -> SSOTokenResponse {
        var request = URLRequest(url: URL(string: "https://login.eveonline.com/v2/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SSOError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(SSOTokenResponse.self, from: data)
    }

    // MARK:  Private

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> SSOTokenResponse {
        var request = URLRequest(url: URL(string: "https://login.eveonline.com/v2/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "code_verifier": codeVerifier
        ]
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw SSOError.tokenExchangeFailed
        }

        return try JSONDecoder().decode(SSOTokenResponse.self, from: data)
    }

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64URLEncodedString()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
}

extension SSOAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}

enum SSOError: LocalizedError {
    case invalidCallback
    case tokenExchangeFailed
    case invalidToken

    var errorDescription: String? {
        switch self {
        case .invalidCallback: return "Invalid authentication callback"
        case .tokenExchangeFailed: return "Failed to exchange authorization code"
        case .invalidToken: return "Invalid or expired token"
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
