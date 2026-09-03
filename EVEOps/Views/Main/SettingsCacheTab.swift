//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import SwiftUI

// MARK:  Cache & Data Tab

struct CacheTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var appCacheSize: String = "Calculating\u{2026}"
    @State private var modelCacheSize: String = "Calculating\u{2026}"
    @State private var isClearingAppCache = false
    @State private var isClearingModels = false
    @State private var isRefreshing = false
    @State private var sdeTag: String?
    @AppStorage(EVEInstallLocator.enabledKey) private var eveLocalEnabled = false
    @State private var eveHasBookmark   = EVEInstallLocator.shared.hasBookmark
    @State private var eveInstallStatus = EVEInstallLocator.shared.statusDescription()
    private let eveStandardPath         = EVEInstallLocator.standardDisplayPath()

    @State private var isScanningCache = false
    @State private var compactionPlan: ResFilesCompactor.Plan?
    @State private var showCompactConfirm = false
    @State private var compactionResultText: String?
    @State private var compactionError: String?

    private var eveStatusColor: Color {
        if eveInstallStatus == "Active" { return .green }
        if eveInstallStatus.hasPrefix("Stale") ||
           eveInstallStatus.hasPrefix("Authorized (ResFiles") { return .orange }
        return .secondary
    }

    var body: some View {
        Form {
            Section("App Caches") {
                LabeledContent("Size", value: appCacheSize)
                Button(isClearingAppCache ? "Clearing\u{2026}" : "Clear Caches") {
                    Task {
                        isClearingAppCache = true
                        await UniverseCache.shared.clearDiskCache()
                        await NameResolver.shared.clearCache()
                        await ESIClient.shared.clearAllCaches()
                        isClearingAppCache = false
                        await recalculateSizes()
                    }
                }
                .disabled(isClearingAppCache)
                Text("Includes universe data, resolved names, and ESI responses. All data re-fetches automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("3D Ship Models") {
                LabeledContent("Size", value: modelCacheSize)
                Button(isClearingModels ? "Clearing\u{2026}" : "Clear Model Cache") {
                    Task {
                        isClearingModels = true
                        await ShipModelService.shared.clearCache()
                        isClearingModels = false
                        await recalculateSizes()
                    }
                }
                .disabled(isClearingModels)
                Text("Downloaded ship meshes and DDS textures. Re-downloaded on demand when viewing ships.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("EVE Installation") {
                LabeledContent("Status") {
                    Text(eveInstallStatus)
                        .foregroundStyle(eveStatusColor)
                }
                if !eveHasBookmark {
                    LabeledContent("Default location") {
                        Text(eveStandardPath)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                if eveHasBookmark {
                    Toggle("Use local textures", isOn: $eveLocalEnabled)
                        .onChange(of: eveLocalEnabled) { _, v in
                            EVEInstallLocator.shared.isEnabled = v
                            refreshEVEStatus()
                        }
                }
                Button(eveHasBookmark ? "Re-authorize\u{2026}" : "Grant Access\u{2026}") {
                    Task { @MainActor in
                        await EVEInstallLocator.shared.presentPicker(in: NSApp.keyWindow)
                        eveLocalEnabled = EVEInstallLocator.shared.isEnabled
                        refreshEVEStatus()
                    }
                }
                if eveHasBookmark {
                    Button("Remove Access") {
                        EVEInstallLocator.shared.clearBookmark()
                        eveLocalEnabled = false
                        refreshEVEStatus()
                    }
                    .foregroundStyle(.red)
                }
                Text("When enabled, ship textures are read directly from your EVE installation instead of downloaded from the internet. 3D models always use the online source.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if eveHasBookmark {
                    Divider()
                    Button(isScanningCache ? "Scanning\u{2026}" : "Compact Cache\u{2026}") {
                        Task {
                            isScanningCache = true
                            compactionError = nil
                            compactionResultText = nil
                            do {
                                let plan = try await Task.detached(priority: .utility) {
                                    try ResFilesCompactor.scan()
                                }.value
                                isScanningCache = false
                                if plan.orphanedFiles.isEmpty {
                                    compactionResultText = "No unused files found."
                                } else {
                                    compactionPlan = plan
                                    showCompactConfirm = true
                                }
                            } catch {
                                isScanningCache = false
                                compactionError = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isScanningCache)
                    .confirmationDialog(
                        compactionPlan.map {
                            "Move \($0.orphanedFiles.count) unused file\($0.orphanedFiles.count == 1 ? "" : "s") (\(formatBytes($0.reclaimableBytes))) to the Trash?"
                        } ?? "",
                        isPresented: $showCompactConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Move to Trash", role: .destructive) {
                            guard let plan = compactionPlan else { return }
                            Task {
                                let result = await Task.detached(priority: .utility) {
                                    ResFilesCompactor.compact(plan)
                                }.value
                                compactionPlan = nil
                                compactionResultText = "Moved \(result.filesRemoved) file\(result.filesRemoved == 1 ? "" : "s") (\(formatBytes(result.bytesReclaimed))) to the Trash."
                            }
                        }
                    }
                    if let compactionResultText {
                        Text(compactionResultText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let compactionError {
                        Text(compactionError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("CCP's own client applies patches additively, so ResFiles content replaced by an update is never deleted automatically. Compact Cache finds content no longer referenced by your installed manifest and moves it to the Trash — never a permanent delete, and never anything still in use.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            EVELaunchView()

            Section("Dashboard Data") {
                LabeledContent("Last refreshed") {
                    if let lastRefresh = prefetcher.lastRefresh {
                        Text(lastRefresh, style: .relative)
                    } else {
                        Text("Never")
                    }
                }
                Button(isRefreshing ? "Refreshing\u{2026}" : "Refresh All Data Now") {
                    Task {
                        isRefreshing = true
                        await prefetcher.prefetchAll(accountManager: accountManager)
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing || prefetcher.isLoading)
            }

            Section("Data Sources") {
                LabeledContent("SDE (EVEShipFit/data)") {
                    Text(sdeTag ?? "Not downloaded")
                        .foregroundStyle(sdeTag != nil ? .primary : .secondary)
                }
                LabeledContent("ESI", value: "latest")
                LabeledContent("EVE Scout", value: "v2")
                LabeledContent("Janice Appraisal", value: "v2")
                LabeledContent("Fuzzwork Market", value: "Live")
                LabeledContent("zKillboard", value: "Live")
                Text("SDE updates automatically when EVEShipFit releases a new dataset. Other APIs always serve current data.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            sdeTag = SDEDataManager.shared.cachedTag()
            await recalculateSizes()
            refreshEVEStatus()
        }
    }

    private func recalculateSizes() async {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appBytes = directorySize(caches.appendingPathComponent("EVEOps/universe"))
                     + fileSize(caches.appendingPathComponent("EVEOps/name_cache.json"))
        appCacheSize = formatBytes(appBytes)
        modelCacheSize = formatBytes(directorySize(appSupport.appendingPathComponent("EVEOps/ModelCache")))
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    private func fileSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "Empty" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func refreshEVEStatus() {
        eveHasBookmark   = EVEInstallLocator.shared.hasBookmark
        eveInstallStatus = EVEInstallLocator.shared.statusDescription()
    }
}
