//
// SimulateFittingView.swift
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

import SwiftUI

// MARK:  Main View

// Walks the AppKit view hierarchy to set autosaveName on the backing NSSplitView,
// which makes macOS persist and restore each divider position automatically.
private struct SplitViewAutosave: NSViewRepresentable {
    let name: String
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { Self.apply(to: v, name: name) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    private static func apply(to view: NSView, name: String) {
        var candidate: NSView? = view.superview
        while let v = candidate {
            if let split = v as? NSSplitView {
                split.autosaveName = NSSplitView.AutosaveName(name)
                return
            }
            candidate = v.superview
        }
    }
}

struct SimulateFittingView: View {
    @State private var simState = SimulatorState()
    @Environment(AccountManager.self) private var accountManager
    @State private var importedEFTEntry: SavedFittingEntry?
    @State private var showImportSaveSheet = false

    var body: some View {
        HSplitView {
            SimLeftPanel()
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                .environment(simState)

            SimFittingDiagram()
                .frame(minWidth: 380)
                .environment(simState)

            SimStatsPanel()
                .frame(minWidth: 280, idealWidth: 300, maxWidth: 360)
                .environment(simState)
        }
        .background(SplitViewAutosave(name: "SimulateFittingView.split"))
        .task {
            simState.isLoadingSDE = true
            await SDEDataManager.shared.ensureLoaded()
            if let path = await SDEDataManager.shared.pbDirPath {
                DogmaEngine.shared.prepare(pbDirPath: path)
            }
            simState.isLoadingSDE = false
            simState.recomputeStats()
        }
        .task { await simState.loadImplants(accountManager: accountManager) }
        .task { await simState.loadSkills(accountManager: accountManager) }
        .onChange(of: accountManager.selectedAccount?.characterID) { _, _ in
            Task { await simState.loadImplants(accountManager: accountManager) }
            Task { await simState.loadSkills(accountManager: accountManager) }
        }
        .onAppear {
            if let url = AppRouter.shared.pendingEFTURL {
                Task { await importEFTFile(url) }
            }
        }
        .onChange(of: AppRouter.shared.pendingEFTURL) { _, url in
            guard let url else { return }
            Task { await importEFTFile(url) }
        }
        .sheet(isPresented: $showImportSaveSheet) {
            if let entry = importedEFTEntry {
                EFTImportSaveSheet(entry: entry) { loadEntry in
                    Task { await simState.loadFromSavedFitting(loadEntry) }
                }
                .environment(accountManager)
            }
        }
    }

    private func importEFTFile(_ url: URL) async {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let parsed = try EFTSerializer.parse(eftText: text)
            guard let account = accountManager.selectedAccount,
                  let token = try? await accountManager.validToken(for: account) else { return }
            let (shipTypeId, name, items) = try await EFTSerializer.resolve(
                parsed: parsed, account: account, token: token
            )
            let entry = SavedFittingEntry(
                characterID: 0, characterName: "",
                fittingId: 0, name: name, fittingDescription: "",
                shipTypeId: shipTypeId, shipTypeName: parsed.shipTypeName,
                shipClassName: "", items: items
            )
            importedEFTEntry = entry
            showImportSaveSheet = true
        } catch {}
        AppRouter.shared.pendingEFTURL = nil
    }
}
