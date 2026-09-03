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


// Mark:  Character Card

struct CharacterCardView: View {
    let account: StoredAccount
    let summary: CharacterSummary?

    @Environment(AccountManager.self) private var accountManager
    @Environment(APIStatusMonitor.self) private var apiStatus
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var liveCorpName: String?
    @State private var liveAllianceName: String?
    @State private var now = Date()
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300

    // Live training data — same pattern as CharacterHeroView
    @State private var liveSkillName: String?
    @State private var liveSkillLevel: Int?
    @State private var liveSkillStart: Date?
    @State private var liveSkillFinish: Date?
    @State private var liveLevelStartSP: Int?
    @State private var liveLevelEndSP: Int?
    @State private var liveTrainingStartSP: Int?
    @State private var liveQueueCount: Int = 0
    @State private var liveQueueEnd: Date?
    @State private var liveQueueEmpty: Bool = true
    @State private var liveQueueLoaded = false

    private var queueIsEmpty: Bool      { liveQueueLoaded ? liveQueueEmpty  : (summary?.isQueueEmpty    ?? true) }
    private var queueSkillName: String? { liveQueueLoaded ? liveSkillName   : summary?.trainingSkillName }
    private var queueSkillLevel: Int?   { liveQueueLoaded ? liveSkillLevel  : summary?.trainingSkillLevel }
    private var queueSkillStart: Date?  { liveQueueLoaded ? liveSkillStart  : summary?.currentSkillStart }
    private var queueSkillFinish: Date? { liveQueueLoaded ? liveSkillFinish : summary?.currentSkillFinish }
    private var queueCount: Int         { liveQueueLoaded ? liveQueueCount  : (summary?.skillQueueCount ?? 0) }
    private var queueEndDate: Date?     { liveQueueLoaded ? liveQueueEnd    : summary?.queueEnd }

    private var trainingProgress: Double {
        guard let start = queueSkillStart, let finish = queueSkillFinish,
              let startSP = liveLevelStartSP, let endSP = liveLevelEndSP, endSP > startSP
        else { return 0 }
        let totalDuration = finish.timeIntervalSince(start)
        guard totalDuration > 0 else { return 1 }
        let elapsed = now.timeIntervalSince(start)
        let fraction = min(max(elapsed / totalDuration, 0), 1)
        let trainingStart = liveTrainingStartSP ?? startSP
        let currentSP = trainingStart + Int(Double(endSP - trainingStart) * fraction)
        return min(max(Double(currentSP - startSP) / Double(endSP - startSP), 0), 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // #3: Status accent stripe — color signals state at a glance
            Rectangle()
                .fill(cardAccentColor)
                .frame(height: 3)

            // #1 + #2: Banner with gradient fade at bottom
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let ship = summary?.ship {
                        CachedAsyncImage(url: EVEImageURL.typeRender(ship.shipTypeId, size: 1024)) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 130)
                                    .clipped()
                            default:
                                bannerPlaceholder
                            }
                        }
                    } else {
                        bannerPlaceholder
                    }
                }

                // #2: Gradient vignette darkens the banner bottom for portrait overlap contrast
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.70)],
                    startPoint: .init(x: 0.5, y: 0.25),
                    endPoint: .bottom
                )
                .frame(height: 130)
                .allowsHitTesting(false)

            }
            .frame(height: 130)

            // #1: Content pulled up to overlap the banner bottom
            VStack(alignment: .leading, spacing: 10) {
                // Identity row — portrait floats above the banner boundary
                HStack(spacing: 12) {
                    CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 512)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                    }
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .overlay(alignment: .bottomTrailing) {
                        CachedAsyncImage(url: EVEImageURL.corporationLogo(account.corporationID, size: 256)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .shadow(color: .black.opacity(0.6), radius: 3)
                            }
                        }
                        .offset(x: 4, y: 4)
                    }
                    .shadow(color: .black.opacity(0.55), radius: 7, y: 3)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.characterName)
                                .font(.headline)
                            Spacer()
                            serverPilotsIndicator
                        }
                        Text(effectiveCorpName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let name = effectiveAllianceName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }

                Divider()

                // Location and ship
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(summary?.systemName ?? "---")
                                .font(.caption)
                            if let systemId = summary?.location?.solarSystemId,
                               WHSpaceInfo.isWormholeSystem(systemId) {
                                let whInfo = WHSpaceInfo.info(systemId: systemId, systemName: summary?.systemName, regionName: summary?.regionName)
                                Text(whInfo?.whClass.shortName ?? "WH")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.purple)
                            } else if let sec = summary?.securityStatus {
                                Text(String(format: "%.1f", sec))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(sec >= 0.5 ? .green : sec >= 0.0 ? .yellow : .red)
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if let ship = summary?.ship {
                            CachedAsyncImage(url: EVEImageURL.typeIcon(ship.shipTypeId, size: 256)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .frame(width: 20, height: 20)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                } else {
                                    Image(systemName: "airplane")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(summary?.ship?.shipName ?? "---")
                                .font(.caption)
                                .lineLimit(1)
                            Text(summary?.shipTypeName ?? "---")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Divider()

                // Wallet & SP
                HStack {
                    Label {
                        Text(EVEFormatters.formatISKShort(summary?.wallet ?? 0))
                            .font(.caption.monospacedDigit())
                    } icon: {
                        Image(systemName: "creditcard.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }

                    Spacer()

                    Label {
                        Text(formatSP(summary?.totalSP ?? 0))
                            .font(.caption.monospacedDigit())
                    } icon: {
                        Image(systemName: "brain.head.profile.fill")
                            .foregroundStyle(.cyan)
                            .font(.caption)
                    }
                }

                // Today's ISK (calendar day, resets at local midnight)
                HStack(spacing: 10) {
                    if let s = summary, s.dailyISKMade > 0 || s.dailyISKSpent > 0 {
                        Label {
                            Text("+\(EVEFormatters.formatISKShort(s.dailyISKMade))")
                                .font(.caption2.monospacedDigit())
                        } icon: {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption2)
                        }
                        Label {
                            Text("-\(EVEFormatters.formatISKShort(s.dailyISKSpent))")
                                .font(.caption2.monospacedDigit())
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption2)
                        }
                    } else {
                        Label {
                            Text("No ISK activity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    Spacer()
                    Text("Today")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // #5: Skill queue with progress bar
                skillQueueRow

                // Industry & Contracts
                HStack {
                    if let s = summary, s.activeIndustryJobCount > 0 {
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(s.activeIndustryJobCount) job\(s.activeIndustryJobCount == 1 ? "" : "s")")
                                    .font(.caption)
                                if let next = s.nextJobFinish {
                                    Text("Next: \(EVEFormatters.timeUntil(next))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.purple)
                                .font(.caption)
                        }
                    } else {
                        Label {
                            Text("No jobs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "hammer.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    Spacer()

                    if let s = summary, s.activeContractCount > 0 {
                        Label {
                            Text("\(s.activeContractCount) active")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.teal)
                                .font(.caption)
                        }
                    } else {
                        Label {
                            Text("No contracts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }

                // PI status
                if let s = summary, s.colonyCount > 0 {
                    HStack {
                        Label {
                            Text("\(s.colonyCount) colon\(s.colonyCount == 1 ? "y" : "ies")")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "globe.americas.fill")
                                .foregroundStyle(.mint)
                                .font(.caption)
                        }

                        Spacer()

                        if s.expiredExtractorCount > 0 {
                            Label {
                                Text("\(s.expiredExtractorCount) offline")
                                    .font(.caption.bold())
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                    .font(.caption)
                            }
                        } else {
                            Text("All running")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Load error banner — shown when the ESI fetch failed for this character
                if let err = summary?.loadError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.85))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.red.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(12)
            .padding(.top, -38)  // #1: portrait overlaps banner by ~28pt
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            Task { await fetchIdentity() }
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in Task { await fetchIdentity() } }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
        .task(id: account.characterID) {
            liveQueueLoaded = false
            await fetchSkillQueue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await fetchSkillQueue()
            }
        }
    }

    private func fetchSkillQueue() async {
        guard let token = try? await accountManager.validToken(for: account),
              let queue: [ESISkillQueue] = try? await ESIClient.shared.fetch(
                  "/characters/\(account.characterID)/skillqueue/",
                  token: token,
                  bypassCache: true
              )
        else { return }
        let sorted = queue.sorted { $0.queuePosition < $1.queuePosition }
        let active = sorted.filter { $0.finishDate ?? .distantPast > Date() }
        let current = active.first {
            ($0.startDate ?? .distantFuture) <= Date() && ($0.finishDate ?? .distantPast) > Date()
        } ?? active.first
        var skillName: String?
        if let skillID = current?.skillId {
            let resolved = await NameResolver.shared.resolve(ids: [skillID])
            skillName = resolved[skillID]
        }
        liveSkillName        = skillName
        liveSkillLevel       = current?.finishedLevel
        liveSkillStart       = current?.startDate
        liveSkillFinish      = current?.finishDate
        liveLevelStartSP     = current?.levelStartSp
        liveLevelEndSP       = current?.levelEndSp
        liveTrainingStartSP  = current?.trainingStartSp
        liveQueueCount       = active.count
        liveQueueEnd         = active.last?.finishDate
        liveQueueEmpty       = active.isEmpty
        liveQueueLoaded      = true
    }

    // #3: Accent stripe color based on most critical state
    private var cardAccentColor: Color {
        guard let s = summary else { return Color(white: 0.25) }
        if s.loadError != nil { return .red }
        if s.expiredExtractorCount > 0 { return .red }
        if s.isQueueEmpty { return .orange }
        if s.online { return .green }
        return Color(white: 0.25)
    }

    // #4: EVE server population, in place of the old per-character online/offline dot
    @ViewBuilder
    private var serverPilotsIndicator: some View {
        if let players = apiStatus.playersOnline {
            HStack(spacing: 4) {
                Circle()
                    .fill(apiStatus.vipMode ? Color.yellow : Color.green)
                    .frame(width: 8, height: 8)
                    .shadow(color: (apiStatus.vipMode ? Color.yellow : Color.green).opacity(0.7), radius: 4)
                Text("\(players.formatted()) online")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .help(serverUptimeTooltip)
        }
    }

    private var serverUptimeTooltip: String {
        guard let start = apiStatus.serverStartTime else { return "Tranquility" }
        let uptime = EVEFormatters.formatDuration(max(Int(Date().timeIntervalSince(start)), 0))
        return "Tranquility — up \(uptime)"
    }

    private var effectiveCorpName: String {
        if let live = liveCorpName { return live }
        if let s = summary, !s.corporationName.isEmpty { return s.corporationName }
        return account.corporationName
    }

    private var effectiveAllianceName: String? {
        liveAllianceName ?? summary?.allianceName ?? account.allianceName
    }

    private func fetchIdentity() async {
        guard let charInfo: ESICharacterPublic = try? await ESIClient.shared.fetch(
            "/characters/\(account.characterID)/"
        ) else { return }
        if let corpInfo: ESICorporationPublic = try? await ESIClient.shared.fetch(
            "/corporations/\(charInfo.corporationId)/"
        ) {
            liveCorpName = corpInfo.name
        }
        if let allianceId = charInfo.allianceId,
           let allianceInfo: ESIAlliancePublic = try? await ESIClient.shared.fetch(
               "/alliances/\(allianceId)/"
           ) {
            liveAllianceName = allianceInfo.name
        } else {
            liveAllianceName = nil
        }
    }

    // #5: Skill queue row with training progress bar
    @ViewBuilder
    private var skillQueueRow: some View {
        if queueIsEmpty {
            Label {
                Text("Training Queue empty!")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        } else {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(queueSkillName ?? "Training...")
                            .font(.caption)
                            .lineLimit(1)
                        if let finish = queueSkillFinish {
                            Spacer()
                            Text(timeUntil(finish))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: trainingProgress)
                        .tint(.blue)
                        .frame(height: 3)

                    HStack(spacing: 4) {
                        Text("\(queueCount) skill\(queueCount == 1 ? "" : "s") in queue")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let end = queueEndDate {
                            Spacer()
                            Text("Ends: \(timeUntil(end))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } icon: {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
            }
        }
    }

    // #7: EVE-themed placeholder with subtle tech-grid aesthetic
    private var bannerPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.09), Color(white: 0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { ctx, size in
                let spacing: CGFloat = 22
                var path = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += spacing
                }
                ctx.stroke(path, with: .color(Color(red: 0, green: 0.75, blue: 1).opacity(0.07)), lineWidth: 0.5)
            }

            if !apiStatus.isReachable {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(apiStatus.statusMessage.isEmpty ? "No connection" : apiStatus.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            } else if summary == nil {
                ProgressView().scaleEffect(0.7)
            }
        }
        .frame(height: 130)
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Done" }
        return EVEFormatters.formatDuration(Int(interval))
    }
}

