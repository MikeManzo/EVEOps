//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import CommonCrypto
import CryptoKit
import Foundation

/// A passphrase-encrypted export of all pilots, for moving to another Mac or keeping an
/// offline copy. Refresh tokens are credentials, so the file is never plaintext:
/// PBKDF2-HMAC-SHA256 stretches the passphrase into an AES-256-GCM key, and the format
/// header is authenticated along with the ciphertext.
///
/// `nonisolated` so the deliberately slow key derivation can run off the main actor.
nonisolated enum PilotBackupFile {
    static let fileExtension = "eveopspilots"
    static let defaultIterations = 600_000
    static let minimumPassphraseLength = 8

    enum Failure: Error, LocalizedError {
        case notABackupFile
        case wrongPassphraseOrDamaged
        case keyDerivationFailed

        var errorDescription: String? {
            switch self {
            case .notABackupFile: "This isn't an EVEOps pilot backup file."
            case .wrongPassphraseOrDamaged: "Wrong passphrase, or the backup file is damaged."
            case .keyDerivationFailed: "Couldn't process the passphrase."
            }
        }
    }

    private static let format = "EVEOps.PilotBackup.v1"
    private static let maxAcceptedIterations = 5_000_000

    private struct Container: Codable {
        var format: String
        var kdf: String
        var iterations: Int
        var salt: Data
        var sealed: Data
    }

    static func encrypt(_ pilots: [ArchivedPilot], passphrase: String, iterations: Int = defaultIterations) throws -> Data {
        let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
        let key = try deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let plaintext = try JSONEncoder().encode(pilots)
        let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: Data(format.utf8))
        guard let combined = sealed.combined else { throw Failure.keyDerivationFailed }

        let container = Container(format: format, kdf: "pbkdf2-hmac-sha256", iterations: iterations,
                                  salt: salt, sealed: combined)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(container)
    }

    static func decrypt(_ file: Data, passphrase: String) throws -> [ArchivedPilot] {
        guard let container = try? JSONDecoder().decode(Container.self, from: file),
              container.format == format,
              container.kdf == "pbkdf2-hmac-sha256",
              (1...maxAcceptedIterations).contains(container.iterations) else {
            throw Failure.notABackupFile
        }
        let key = try deriveKey(passphrase: passphrase, salt: container.salt, iterations: container.iterations)
        guard let box = try? AES.GCM.SealedBox(combined: container.sealed),
              let plaintext = try? AES.GCM.open(box, using: key, authenticating: Data(format.utf8)),
              let pilots = try? JSONDecoder().decode([ArchivedPilot].self, from: plaintext) else {
            throw Failure.wrongPassphraseOrDamaged
        }
        return pilots
    }

    private static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        // NFKC so the same passphrase typed on different keyboards/IMEs derives the same key.
        let password = Array(passphrase.precomposedStringWithCompatibilityMapping.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltBytes in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                password.map { Int8(bitPattern: $0) }, password.count,
                saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &derived, derived.count
            )
        }
        guard status == kCCSuccess else { throw Failure.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }
}
