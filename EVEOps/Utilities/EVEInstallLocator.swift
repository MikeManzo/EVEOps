// EVEInstallLocator.swift
// EVEOps
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
import AppKit
import OSLog

/// Manages sandbox-safe access to the EVE Online SharedCache on disk.
///
/// Workflow:
///   1. User clicks "Grant Access" in Settings → Cache & Data → EVE Installation.
///   2. NSOpenPanel opens at ~/Library/Application Support/ (real path, not the sandbox
///      container). User clicks on "EVE Online" and clicks "Grant Access".
///   3. The chosen URL is persisted as a security-scoped bookmark in UserDefaults.
///   4. After access is granted, `resolvedSharedCache` reads the EVE launcher's
///      `launcher-data.json` to find the actual SharedCache path (which may be on a
///      custom volume if the user moved it in the EVE Launcher settings).
///   5. `resFilesURL()` returns the ResFiles subdirectory; `ShipModelService` checks
///      it before every CDN texture fetch.
///
/// EVE Online Application Support structure (default path):
///   ~/Library/Application Support/EVE Online/          ← "EVE Online" (all-caps EVE)
///   ├── launcher-data.json                              ← contains actual SharedCache path
///   └── SharedCache/                                    ← default SharedCache location
///       ├── ResFiles/
///       │   ├── 88/
///       │   │   └── 88be22a862a179e3_c78655b8a7cd685b292b7e1758b39039
///       │   └── …
///       └── tq/EVE.app/Contents/Resources/build/
///           └── resfileindex.txt
final class EVEInstallLocator {
    static let shared = EVEInstallLocator()

    private static let log = Logger(subsystem: "CitizenCoder.EVEOps", category: "EVEInstall")

    /// UserDefaults key for the enabled toggle — exposed so the Settings view can bind an
    /// @AppStorage to the same key without going through the locator on every re-render.
    static let enabledKey   = "eveLocalTexturesEnabled"
    private static let bookmarkKey = "eveInstallBookmark"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var hasBookmark: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    // nonisolated(unsafe): written once during startAccess(), read-mostly thereafter.
    private nonisolated(unsafe) var _accessURL:   URL? = nil
    private nonisolated(unsafe) var _isAccessing: Bool = false

    private init() {
        Self.log.info("EVEInstallLocator init — hasBookmark: \(self.hasBookmark, privacy: .public), enabled: \(self.isEnabled, privacy: .public)")
    }

    // MARK: Standard path (navigation hint)

    /// The default EVE Online Application Support folder.
    /// Uses `homeDirectoryForCurrentUser` — in a sandboxed app `urls(for: .applicationSupportDirectory)`
    /// returns the container path, not the real ~/Library/Application Support/.
    static func standardEVEURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/EVE Online")
    }

    /// Standard path abbreviated with `~` for display in Settings.
    static func standardDisplayPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return standardEVEURL().path.replacingOccurrences(of: home, with: "~")
    }

    // MARK: Security-scoped access

    /// Resolves the stored bookmark and starts security-scoped access.
    /// Idempotent — safe to call on every texture request.
    @discardableResult
    func startAccess() -> URL? {
        if _isAccessing, let url = _accessURL { return url }
        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            Self.log.error("Failed to resolve security-scoped bookmark")
            return nil
        }
        if stale {
            Self.log.warning("Security-scoped bookmark is stale — clearing")
            clearBookmark(); return nil
        }
        guard url.startAccessingSecurityScopedResource() else {
            Self.log.error("startAccessingSecurityScopedResource failed: \(url.path, privacy: .public)")
            return nil
        }
        _accessURL   = url
        _isAccessing = true
        Self.log.info("Security-scoped access started: \(url.path, privacy: .public)")
        return url
    }

    func stopAccess() {
        guard _isAccessing, let url = _accessURL else { return }
        url.stopAccessingSecurityScopedResource()
        _isAccessing = false
        _accessURL   = nil
        Self.log.debug("Security-scoped access stopped")
    }

    func clearBookmark() {
        stopAccess()
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        isEnabled = false
        Self.log.info("EVE install bookmark cleared")
    }

    // MARK: Derived paths

    /// Returns the ResFiles directory URL, or nil when access is unavailable,
    /// the feature is disabled, or ResFiles doesn't exist under the resolved SharedCache.
    func resFilesURL() -> URL? {
        guard isEnabled else {
            Self.log.warning("resFilesURL: isEnabled=false")
            return nil
        }
        guard let base = startAccess() else {
            Self.log.warning("resFilesURL: startAccess returned nil")
            return nil
        }
        let rf = resolvedSharedCache(from: base).appendingPathComponent("ResFiles", isDirectory: true)
        return FileManager.default.fileExists(atPath: rf.path) ? rf : nil
    }

    /// Returns the path to the local resfileindex.txt bundled with the EVE client.
    func localResIndexURL() -> URL? {
        guard let base = startAccess() else { return nil }
        let idx = resolvedSharedCache(from: base)
            .appendingPathComponent("tq/EVE.app/Contents/Resources/build/resfileindex.txt")
        return FileManager.default.fileExists(atPath: idx.path) ? idx : nil
    }

    /// Resolves the actual SharedCache directory from the bookmarked root.
    ///
    /// Priority order:
    ///   1. Path from `launcher-data.json` — handles user-customised SharedCache locations
    ///      (EVE Launcher → Settings → Shared Cache lets users choose any volume).
    ///   2. `SharedCache` subdirectory of the selected folder.
    ///   3. The selected folder itself (user picked `SharedCache` directly).
    ///   4. Parent of the selected folder (user picked `ResFiles` directly).
    private func resolvedSharedCache(from base: URL) -> URL {
        // 1. Prefer the launcher's own configuration so custom locations work.
        if let configuredPath = readLauncherSharedCachePath(from: base) {
            let configured = URL(fileURLWithPath: configuredPath)
            if FileManager.default.fileExists(atPath: configured.path) {
                Self.log.debug("Using launcher-configured SharedCache: \(configuredPath, privacy: .public)")
                return configured
            }
        }
        // 2–4. Derive from the folder name.
        switch base.lastPathComponent {
        case "ResFiles":    return base.deletingLastPathComponent()
        case "SharedCache": return base
        default:
            let sc = base.appendingPathComponent("SharedCache")
            return FileManager.default.fileExists(atPath: sc.path) ? sc : base
        }
    }

    /// Reads `launcher-data.json` to find the user-configured SharedCache path.
    /// Searches in and around `base` (the bookmarked root) to locate the file.
    private func readLauncherSharedCachePath(from base: URL) -> String? {
        let candidates = [
            base.appendingPathComponent("launcher-data.json"),
            base.deletingLastPathComponent().appendingPathComponent("launcher-data.json"),
        ]
        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sc   = json["shared-cache"] as? [String: Any],
                  let eve  = sc["eve-online"]      as? [String: Any],
                  let loc  = eve["location"]        as? [String: Any],
                  let path = loc["path"]            as? String
            else { continue }
            return path
        }
        return nil
    }

    // MARK: NSOpenPanel

    /// Presents an NSOpenPanel pre-navigated to ~/Library/Application Support/ so the
    /// user can click on "EVE Online" and grant access in one click.
    /// If the user moved the SharedCache in EVE Launcher settings, they can navigate
    /// to that location instead (any parent folder of SharedCache or ResFiles works).
    @MainActor
    @discardableResult
    func presentPicker(in window: NSWindow?) async -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false
        panel.prompt  = "Grant Access"
        panel.title   = "Grant EVE Online Access"

        // Open the panel INSIDE the standard EVE Online folder so the user just clicks
        // "Grant Access" with no further navigation. When directoryURL points inside a
        // folder and nothing in the list is selected, NSOpenPanel returns that folder itself.
        // Uses homeDirectoryForCurrentUser — sandboxed apps get a container path from
        // urls(for: .applicationSupportDirectory), not the real ~/Library/Application Support/.
        panel.directoryURL = Self.standardEVEURL()

        let displayPath = Self.standardDisplayPath()
        panel.message = """
            EVEOps needs access to read ship textures locally.

            Click "Grant Access" to confirm. If your EVE files are in a different \
            location, navigate there and click "Grant Access".
            """

        let resp: NSApplication.ModalResponse
        if let w = window {
            resp = await panel.beginSheetModal(for: w)
        } else {
            resp = panel.runModal()
        }
        guard resp == .OK, let url = panel.url else {
            Self.log.info("EVE install picker cancelled")
            return false
        }

        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            Self.log.error("Failed to create security-scoped bookmark for \(url.path, privacy: .public)")
            return false
        }

        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        isEnabled = true
        stopAccess()
        _ = startAccess()
        let rfPath = resFilesURL()?.path ?? "not found"
        Self.log.info("EVE install authorized: \(url.path, privacy: .public) → ResFiles: \(rfPath, privacy: .public)")
        return true
    }

    // MARK: Status

    func statusDescription() -> String {
        guard hasBookmark else {
            return "Click \"Grant Access\" to enable local textures"
        }
        guard let base = startAccess() else { return "Stale bookmark — please re-authorize" }
        let rf = resolvedSharedCache(from: base).appendingPathComponent("ResFiles", isDirectory: true)
        guard FileManager.default.fileExists(atPath: rf.path) else {
            return "Authorized (ResFiles not found — wrong folder?)"
        }
        return isEnabled ? "Active" : "Authorized (disabled)"
    }
}
