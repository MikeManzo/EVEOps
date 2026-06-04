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

struct CorporationMoonExtractionsView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var extractions: [ESIMoonExtraction] = []
    @State private var names: [Int: String] = [:]
    @State private var isLoading = false
    @State private var error: String?

    private var sorted: [ESIMoonExtraction] {
        extractions.sorted { $0.chunkArrivalTime < $1.chunkArrivalTime }
    }

    var body: some View {
        LoadingStateView(
            isLoading: isLoading,
            error: error,
            isEmpty: extractions.isEmpty,
            emptyMessage: "No moon extractions scheduled.\n\nMoon drills must be active and your character needs moon mining roles."
        ) {
            List(sorted) { extraction in
                MoonExtractionRow(
                    extraction: extraction,
                    structureName: names[extraction.structureId],
                    moonName: names[extraction.moonId]
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Moon Extractions")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
        .task(id: accountManager.selectedCharacterID) {
            await load()
        }
    }

    private func load() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let token = try await accountManager.validToken(for: account)
            let raw: [ESIMoonExtraction] = try await ESIClient.shared.fetch(
                "/corporation/\(account.corporationID)/mining/extractions/",
                token: token
            )
            extractions = raw
            let ids = Array(Set(raw.map { $0.structureId } + raw.map { $0.moonId }))
            names = await NameResolver.shared.resolve(ids: ids)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK:  Row

struct MoonExtractionRow: View {
    let extraction: ESIMoonExtraction
    let structureName: String?
    let moonName: String?

    @State private var now = Date()

    private var state: ExtractionState {
        if now > extraction.naturalDecayTime { return .decayed }
        if now > extraction.chunkArrivalTime { return .ready }
        return .pending
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.icon)
                .font(.title2)
                .foregroundStyle(state.color)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(structureName ?? "Structure #\(extraction.structureId)")
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(moonName ?? "Moon #\(extraction.moonId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Started \(extraction.extractionStartTime, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                switch state {
                case .pending:
                    Text(EVEFormatters.timeUntil(extraction.chunkArrivalTime))
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.blue)
                    Text("until pop")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                case .ready:
                    Text("Ready")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                    Text("Decays in \(EVEFormatters.timeUntil(extraction.naturalDecayTime))")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                case .decayed:
                    Text("Decayed")
                        .font(.subheadline.bold())
                        .foregroundStyle(.gray)
                    Text(extraction.naturalDecayTime, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(extraction.chunkArrivalTime, style: .date)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }

    enum ExtractionState {
        case pending, ready, decayed
        var icon: String {
            switch self {
            case .pending: return "moon.fill"
            case .ready: return "moon.stars.fill"
            case .decayed: return "moon"
            }
        }
        var color: Color {
            switch self {
            case .pending: return .blue
            case .ready: return .green
            case .decayed: return .gray
            }
        }
    }
}
