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

/// Resolves a pasted Local chat member list into pilot affiliations, security
/// status, and portraits via ESI. See `LocalIntelService` for why this is
/// paste-driven rather than reading anything automatically off disk.
struct LocalIntelView: View {
    @State private var pasteText = ""
    @State private var pilots: [LocalIntelPilot] = []
    @State private var unresolvedNames: [String] = []
    @State private var isLoading = false
    @State private var hasScanned = false
    @State private var selectedPilot: LocalIntelPilot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In EVE, select-all and copy the Local member list (⌘A, ⌘C), then paste it below.")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextEditor(text: $pasteText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: 90, maxHeight: 150)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: EVERadius.sm))
                .overlay(RoundedRectangle(cornerRadius: EVERadius.sm).stroke(.separator))

            controls

            Divider()

            resultsList
        }
        .padding()
        .navigationTitle("Local Intel")
        .sheet(item: $selectedPilot) { pilot in
            LocalIntelPilotDetailView(pilot: pilot)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await scan() }
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Scan Local", systemImage: "binoculars.fill")
                }
            }
            .disabled(isLoading || pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !pasteText.isEmpty {
                Button("Clear") {
                    pasteText = ""
                    pilots = []
                    unresolvedNames = []
                    hasScanned = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if hasScanned {
                Text("\(pilots.count) resolved" + (unresolvedNames.isEmpty ? "" : ", \(unresolvedNames.count) not found"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if !hasScanned {
            ContentUnavailableView(
                "No Scan Yet",
                systemImage: "binoculars",
                description: Text("Paste a Local member list and tap Scan Local.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if pilots.isEmpty && unresolvedNames.isEmpty {
            ContentUnavailableView(
                "No Pilots Found",
                systemImage: "questionmark.circle",
                description: Text("Nothing in the pasted text resolved to a known pilot.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                if !pilots.isEmpty {
                    Section("Pilots") {
                        ForEach(pilots) { pilot in
                            LocalIntelRow(pilot: pilot)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedPilot = pilot }
                                .eveContextMenu(.character(id: pilot.characterId, name: pilot.name))
                        }
                    }
                }
                if !unresolvedNames.isEmpty {
                    Section("Not Found") {
                        ForEach(unresolvedNames, id: \.self) { name in
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func scan() async {
        isLoading = true
        defer { isLoading = false }
        let result = await LocalIntelService.shared.resolve(pastedText: pasteText)
        pilots = result.pilots
        unresolvedNames = result.unresolvedNames
        hasScanned = true
    }
}

private struct LocalIntelRow: View {
    let pilot: LocalIntelPilot

    var body: some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(pilot.characterId, size: 64)) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(.quaternary)
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(pilot.name)
                HStack(spacing: 4) {
                    if let ticker = pilot.corporationTicker {
                        Text("[\(ticker)]")
                    }
                    if let allianceTicker = pilot.allianceTicker {
                        Text("<\(allianceTicker)>")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let danger = pilot.zkbStats?.dangerRatio {
                Text("\(Int(danger))")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(zkbDangerColor(danger))
                    .help("zKillboard danger rating")
            }

            if let securityStatus = pilot.securityStatus {
                Text(String(format: "%.1f", securityStatus))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(pilotSecurityColor(securityStatus))
            }

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
