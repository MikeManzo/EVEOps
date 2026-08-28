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

/// Pure diff between a locally-known manifest and a freshly-fetched remote one. No I/O — the
/// caller is responsible for parsing both sides (typically via `ResourceManifestEntry`) and for
/// actually reading local files to know what's really on disk.
enum ManifestDiffer {
    enum DiffReason: Sendable, Equatable {
        case missingLocally
        case checksumMismatch
        case sizeMismatch
    }

    struct DiffEntry: Sendable, Hashable {
        let entry: ResourceManifestEntry
        let reason: DiffReason
    }

    struct DiffSummary: Sendable, Equatable {
        let filesToDownload: [DiffEntry]
        let totalDownloadBytes: Int
        let filesUpToDate: Int

        static func == (lhs: DiffSummary, rhs: DiffSummary) -> Bool {
            lhs.filesToDownload.map(\.entry) == rhs.filesToDownload.map(\.entry)
                && lhs.totalDownloadBytes == rhs.totalDownloadBytes
                && lhs.filesUpToDate == rhs.filesUpToDate
        }
    }

    static func indexByVirtualPath(_ entries: [ResourceManifestEntry]) -> [String: ResourceManifestEntry] {
        Dictionary(entries.map { ($0.virtualPath, $0) }, uniquingKeysWith: { _, new in new })
    }

    /// `localEntries` should reflect what's actually verified present on disk (e.g. built from
    /// the last-known-good local index, or from re-hashing files during a "Repair"-style pass) —
    /// this function only compares the two entry sets, it doesn't touch the filesystem itself.
    static func diff(
        localEntries: [String: ResourceManifestEntry],
        remoteEntries: [ResourceManifestEntry]
    ) -> DiffSummary {
        var toDownload: [DiffEntry] = []
        var upToDateCount = 0

        for remote in remoteEntries {
            guard let local = localEntries[remote.virtualPath] else {
                toDownload.append(DiffEntry(entry: remote, reason: .missingLocally))
                continue
            }
            if local.checksum != remote.checksum {
                toDownload.append(DiffEntry(entry: remote, reason: .checksumMismatch))
            } else if local.uncompressedSize != remote.uncompressedSize {
                toDownload.append(DiffEntry(entry: remote, reason: .sizeMismatch))
            } else {
                upToDateCount += 1
            }
        }

        let totalBytes = toDownload.reduce(0) { $0 + $1.entry.compressedSize }
        return DiffSummary(filesToDownload: toDownload, totalDownloadBytes: totalBytes, filesUpToDate: upToDateCount)
    }
}
