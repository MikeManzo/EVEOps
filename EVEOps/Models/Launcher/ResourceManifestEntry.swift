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

/// One line of CCP's resource manifest. Two real variants confirmed against files on disk:
///   - App-bundle manifests (`SharedCache/index_tranquility.txt`, `eveonline_{build}.txt`) use
///     LF line endings and 6 fields, the last being unix permissions:
///     "app:/EVE.app/Contents/MacOS/EVE,23/2376c8082e3c8d34_865dcf16e1986a86c26c627ae6d5b548,
///      865dcf16e1986a86c26c627ae6d5b548,151536,14907,33252"
///   - The game-content manifest (`resfileindex.txt`) uses CRLF line endings and only 5 fields
///     (no permissions column, since content files don't need executable bits):
///     "res:/intromovie.txt,a9/a9d1721dd5cc6d54_e6bbb2df307e5a9527159a4c971034b5,
///      e6bbb2df307e5a9527159a4c971034b5,9719,3312"
struct ResourceManifestEntry: Sendable, Hashable {
    let virtualPath: String
    let hashPath: String
    let checksum: String
    let uncompressedSize: Int
    let compressedSize: Int
    let unixPermissions: Int?

    nonisolated static func parseLine(_ line: String) -> ResourceManifestEntry? {
        let fields = line.components(separatedBy: ",")
        guard fields.count >= 5,
              let uncompressed = Int(fields[3]),
              let compressed = Int(fields[4]) else { return nil }
        return ResourceManifestEntry(
            virtualPath: fields[0],
            hashPath: fields[1],
            checksum: fields[2],
            uncompressedSize: uncompressed,
            compressedSize: compressed,
            unixPermissions: fields.count >= 6 ? Int(fields[5]) : nil
        )
    }

    nonisolated static func parseIndex(_ text: String) -> [ResourceManifestEntry] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .compactMap { line in line.isEmpty ? nil : parseLine(line) }
    }
}
