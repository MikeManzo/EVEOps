//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

/// Decodes the character identity out of a CCP SSO JWT access token's payload — shared by
/// every OAuth client this app authenticates with (ESI's `AccountManager` and the launcher's
/// `LauncherAccountManager`), since CCP issues the same JWT shape regardless of client_id.
func decodeSSOJWT(_ token: String) throws -> ESITokenCharacter {
    let parts = token.split(separator: ".")
    guard parts.count == 3 else { throw SSOError.invalidToken }

    var base64 = String(parts[1])
    while base64.count % 4 != 0 {
        base64.append("=")
    }
    base64 = base64.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    guard let data = Data(base64Encoded: base64) else { throw SSOError.invalidToken }

    struct JWTPayload: Codable {
        let sub: String
        let name: String
        let scp: ScopeValue?
        let exp: Int

        enum ScopeValue: Codable {
            case single(String)
            case multiple([String])

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let array = try? container.decode([String].self) {
                    self = .multiple(array)
                } else if let string = try? container.decode(String.self) {
                    self = .single(string)
                } else {
                    self = .multiple([])
                }
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                case .single(let s): try container.encode(s)
                case .multiple(let a): try container.encode(a)
                }
            }

            var scopes: [String] {
                switch self {
                case .single(let s): return [s]
                case .multiple(let a): return a
                }
            }
        }
    }

    let payload = try JSONDecoder().decode(JWTPayload.self, from: data)
    // CCP's SSO issues different `sub` prefixes depending on the client: ESI tokens use
    // "CHARACTER:EVE:<id>", while the launcher client (eveLauncherTQ) uses "USER:EVE:<id>" for
    // its account-level identity. Take whatever follows the last colon rather than hardcoding
    // one prefix, so both (and any future variant) resolve correctly.
    let characterIDString = payload.sub.components(separatedBy: ":").last ?? payload.sub
    guard let characterID = Int(characterIDString) else { throw SSOError.invalidToken }

    return ESITokenCharacter(
        characterID: characterID,
        characterName: payload.name,
        scopes: payload.scp?.scopes ?? [],
        expiresOn: Date(timeIntervalSince1970: TimeInterval(payload.exp))
    )
}
