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
import OSLog

/// Finds and removes content-addressed files under `ResFiles` that are no longer referenced by
/// any locally-installed manifest.
///
/// CCP's own client patches this store additively (a changed virtual path just gets a new
/// hash-addressed file; the old one is never deleted), so `ResFiles` accumulates orphaned content
/// across patches over time — the only built-in remedy is a full "Clear Cache" wipe. This offers
/// a safer, selective alternative.
///
/// Safety: a file only counts as orphaned if it appears in NEITHER local manifest. Both the
/// app-bundle manifest (`index_tranquility.txt` — EVE.app's own binaries/resources) and the
/// game-content manifest (`resfileindex.txt` — everything else) point into the same
/// content-addressed `ResFiles` store, confirmed by their identical hashPath format. Missing
/// either one from the referenced set would misclassify in-use files as orphaned and could break
/// the installed client. `compact` never permanently deletes — it moves files to the user's
/// Trash, so a bad scan can always be undone by hand.
enum ResFilesCompactor {
    private static let log = Logger(subsystem: "CitizenCoder.EVEOps", category: "ResFilesCompactor")

    struct Plan: Sendable {
        let orphanedFiles: [URL]
        let reclaimableBytes: Int64
    }

    enum CompactorError: LocalizedError {
        case noLocalInstall
        var errorDescription: String? {
            "Grant EVE Online access in Settings → Cache & Data → EVE Installation first."
        }
    }

    /// Dry run: walks the real `ResFiles` tree and reports what *would* be moved to the Trash.
    /// Never modifies anything itself.
    static func scan() throws -> Plan {
        guard let resFiles = EVEInstallLocator.shared.resFilesWritableURL() else {
            throw CompactorError.noLocalInstall
        }
        let referenced = referencedHashPaths()

        var orphaned: [URL] = []
        var bytes: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: resFiles,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return Plan(orphanedFiles: [], reclaimableBytes: 0)
        }

        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let relativePath = fileURL.pathComponents.suffix(2).joined(separator: "/")
            guard !referenced.contains(relativePath) else { continue }
            orphaned.append(fileURL)
            bytes += Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        log.info("Compaction scan: \(orphaned.count, privacy: .public) orphaned files, \(bytes, privacy: .public) bytes, out of \(referenced.count, privacy: .public) referenced hash paths")
        return Plan(orphanedFiles: orphaned, reclaimableBytes: bytes)
    }

    /// Moves every file in `plan` to the user's Trash — never a permanent delete.
    @discardableResult
    static func compact(_ plan: Plan) -> (filesRemoved: Int, bytesReclaimed: Int64) {
        var removed = 0
        var bytesRemoved: Int64 = 0
        for url in plan.orphanedFiles {
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
                removed += 1
                bytesRemoved += size
            } else {
                log.error("Failed to trash \(url.path, privacy: .public)")
            }
        }
        log.info("Compaction complete: moved \(removed, privacy: .public) files (\(bytesRemoved, privacy: .public) bytes) to Trash")
        return (removed, bytesRemoved)
    }

    private static func referencedHashPaths() -> Set<String> {
        var paths = Set<String>()
        if let appIndexURL = EVEInstallLocator.shared.localAppIndexURL(),
           let text = try? String(contentsOf: appIndexURL, encoding: .utf8) {
            paths.formUnion(ResourceManifestEntry.parseIndex(text).map(\.hashPath))
        }
        if let resIndexURL = EVEInstallLocator.shared.localResIndexURL(),
           let text = try? String(contentsOf: resIndexURL, encoding: .utf8) {
            paths.formUnion(ResourceManifestEntry.parseIndex(text).map(\.hashPath))
        }
        return paths
    }
}
