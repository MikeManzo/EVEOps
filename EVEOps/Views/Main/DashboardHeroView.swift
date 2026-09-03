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

// MARK: Character Hero Card

struct CharacterHeroView: View {
    let account: StoredAccount
    let summary: CharacterSummary?

    @Environment(AccountManager.self) private var accountManager
    @Environment(APIStatusMonitor.self) private var apiStatus
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var liveCorpName: String?
    @State private var liveAllianceName: String?
    @State private var liveAllianceID: Int?
    @State private var liveSecurityStatus: Double?
    @State private var liveTitle: String?
    @State private var liveBirthday: Date?
    @State private var liveAttributes: ESICharacterAttributes?
    @State private var liveCloneJumpReadyAt: Date?
    @State private var liveStationName: String?
    @State private var pulsing = false
    @State private var now = Date()
    @AppStorage("backgroundPollInterval") private var pollInterval: Double = 300

    // Live training data fetched directly from ESI (same pattern as TrainingOverviewView)
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

    // Attribute pill detail-panel support
    @State private var liveImplantBonuses: [String: Int] = [:]
    @State private var liveImplantsResolved = false
    @State private var liveTrainingPrimaryAttr: SkillTrainingAttribute?
    @State private var liveTrainingSecondaryAttr: SkillTrainingAttribute?
    @State private var expandedAttr: SkillTrainingAttribute?

    private var queueIsEmpty: Bool      { liveQueueLoaded ? liveQueueEmpty  : (summary?.isQueueEmpty    ?? true) }
    private var queueSkillName: String? { liveQueueLoaded ? liveSkillName   : summary?.trainingSkillName }
    private var queueSkillLevel: Int?   { liveQueueLoaded ? liveSkillLevel  : summary?.trainingSkillLevel }
    private var queueSkillStart: Date?  { liveQueueLoaded ? liveSkillStart  : summary?.currentSkillStart }
    private var queueSkillFinish: Date? { liveQueueLoaded ? liveSkillFinish : summary?.currentSkillFinish }
    private var queueCount: Int         { liveQueueLoaded ? liveQueueCount  : (summary?.skillQueueCount ?? 0) }
    private var queueEndDate: Date?     { liveQueueLoaded ? liveQueueEnd    : summary?.queueEnd }

    // SP-based progress — matches TrainingOverviewView.estimateCurrentSP exactly
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
            Rectangle()
                .fill(cardAccentColor)
                .frame(height: 3)

            HStack(alignment: .top, spacing: 0) {
                leftIdentityPanel
                    .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .padding(.vertical, 16)

                characterMetricsPanel
                    .frame(width: 284)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            Task { await fetchIdentity() }
            if summary?.online == true {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
        }
        .onChange(of: prefetcher.lastRefresh) { _, _ in Task { await fetchIdentity() } }
        .onChange(of: summary?.online) { _, online in
            if online == true {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            } else {
                withAnimation(.default) { pulsing = false }
            }
        }
        .task(id: locationTaskID) { await fetchStationName() }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                now = Date()
            }
        }
        .task(id: "skillQueue") {
            await fetchSkillQueue()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                await fetchSkillQueue()
            }
        }
    }

    private var locationTaskID: String {
        if let s = summary?.location?.stationId { return "st\(s)" }
        if let s = summary?.location?.structureId { return "str\(s)" }
        return "none"
    }

    private func fetchStationName() async {
        guard let loc = summary?.location else { return }
        if let stationId = loc.stationId {
            if let station: ESIStation = try? await ESIClient.shared.fetch(
                "/universe/stations/\(stationId)/"
            ) {
                liveStationName = station.name
            }
        } else if let structureId = loc.structureId,
                  let token = try? await accountManager.validToken(for: account) {
            let strID = structureId
            if let structure: ESIStructure = try? await ESIClient.shared.fetch(
                "/universe/structures/\(strID)/", token: token
            ) {
                liveStationName = structure.name
            }
        } else {
            liveStationName = nil
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
        var primaryAttr: SkillTrainingAttribute?
        var secondaryAttr: SkillTrainingAttribute?
        if let skillID = current?.skillId {
            let resolved = await NameResolver.shared.resolve(ids: [skillID])
            skillName = resolved[skillID]
            if let dogma = await UniverseCache.shared.type(id: skillID)?.dogmaAttributes {
                if let pID = dogma.first(where: { $0.attributeId == 180 }).map({ Int($0.value) }) {
                    primaryAttr = SkillTrainingAttribute.from(dogmaID: pID)
                }
                if let sID = dogma.first(where: { $0.attributeId == 181 }).map({ Int($0.value) }) {
                    secondaryAttr = SkillTrainingAttribute.from(dogmaID: sID)
                }
            }
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
        liveTrainingPrimaryAttr   = primaryAttr
        liveTrainingSecondaryAttr = secondaryAttr
    }

    @ViewBuilder
    private var leftIdentityPanel: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let ship = summary?.ship {
                        CachedAsyncImage(url: EVEImageURL.typeRender(ship.shipTypeId, size: 1024)) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 140)
                                    .clipped()
                            default:
                                bannerPlaceholder
                            }
                        }
                    } else {
                        bannerPlaceholder
                    }
                }

                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.70)],
                    startPoint: .init(x: 0.5, y: 0.25),
                    endPoint: .bottom
                )
                .frame(height: 140)
                .allowsHitTesting(false)

            }
            .frame(height: 140)
            .clipped()
            .allowsHitTesting(false)   // banner is purely decorative; a fill-mode AsyncImage's
                                       // un-clipped bounds otherwise swallow clicks on the card below

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 512)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 14).fill(.quaternary)
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.22), lineWidth: 1.5))
                    .overlay(alignment: .bottomTrailing) {
                        CachedAsyncImage(url: EVEImageURL.corporationLogo(account.corporationID, size: 256)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .frame(width: 26, height: 26)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    .shadow(color: .black.opacity(0.6), radius: 4)
                            }
                        }
                        .offset(x: 4, y: 4)
                    }
                    .shadow(color: .black.opacity(0.60), radius: 10, y: 4)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            if let birthday = liveBirthday {
                                let years = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
                                Text("\(account.characterName), \(years) years old")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 1)
                            } else {
                                Text(account.characterName)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 1)
                            }
                            Spacer()
                            onlineIndicator
                        }
                        .padding(.bottom, 7)
                        HStack(spacing: 6) {
                            Text(effectiveCorpName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let title = liveTitle {
                                Text(title)
                                    .font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                                    .lineLimit(1)
                            }
                        }
                        if let name = effectiveAllianceName {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }

                        Divider().padding(.vertical, 2)

                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundStyle(.blue)
                                    .font(.callout)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(summary?.systemName ?? "---")
                                            .font(.callout.weight(.medium))
                                        if let systemId = summary?.location?.solarSystemId,
                                           WHSpaceInfo.isWormholeSystem(systemId) {
                                            let whInfo = WHSpaceInfo.info(systemId: systemId, systemName: summary?.systemName, regionName: summary?.regionName)
                                            Text(whInfo?.whClass.shortName ?? "WH")
                                                .font(.caption.bold())
                                                .foregroundStyle(.purple)
                                        } else if let sec = summary?.securityStatus {
                                            Text(String(format: "%.1f", sec))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(sec >= 0.5 ? .green : sec >= 0.0 ? .yellow : .red)
                                        }
                                    }
                                    if let station = liveStationName {
                                        Text(station)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            HStack(spacing: 8) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(summary?.ship?.shipName ?? "---")
                                        .font(.callout.weight(.medium))
                                        .lineLimit(1)
                                    Text(summary?.shipTypeName ?? "---")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if let ship = summary?.ship {
                                    CachedAsyncImage(url: EVEImageURL.typeIcon(ship.shipTypeId, size: 256)) { phase in
                                        if let image = phase.image {
                                            image.resizable()
                                                .frame(width: 36, height: 36)
                                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                        } else {
                                            Image(systemName: "airplane")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 36, height: 36)
                                        }
                                    }
                                }
                            }
                        }

                        HStack(spacing: 0) {
                            if let sec = liveSecurityStatus {
                                HStack(spacing: 4) {
                                    Image(systemName: "shield.fill")
                                        .font(.caption2)
                                        .foregroundStyle(sec >= 0 ? .green : .red)
                                    Text(String(format: "%.2f", sec))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(sec >= 0 ? .green : .red)
                                    Text("Security Status")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Image(systemName: "brain.head.profile.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan)
                                Text(formatSP(summary?.totalSP ?? 0))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text("SP")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                // Training progress block
                Divider()
                trainingProgressBlock

                // Attribute pills
                Divider()
                attributePillsRow

                // Clone jump timer (only when character has jump clones)
                if let readyAt = liveCloneJumpReadyAt {
                    Divider()
                    cloneJumpRow(readyAt: readyAt)
                }

                // Alliance identity flourish — only when in an alliance
                if let allianceID = liveAllianceID, let allianceName = effectiveAllianceName {
                    Divider()
                    allianceFlourishRow(id: allianceID, name: allianceName)
                }

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
            .padding(.top, -38)
        }
    }

    @ViewBuilder
    private var trainingProgressBlock: some View {
        if queueIsEmpty {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Training queue is empty")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    HStack(spacing: 3) {
                        Text(queueSkillName ?? "Training...")
                            .font(.caption)
                            .lineLimit(1)
                        if let level = queueSkillLevel {
                            Text("→ \(romanNumeral(level))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let finish = queueSkillFinish {
                        Text(timeUntil(finish))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if liveLevelStartSP != nil || queueSkillStart != nil {
                    ProgressView(value: trainingProgress)
                        .tint(.blue)
                        .frame(height: 3)
                }
                HStack(spacing: 4) {
                    Text("\(queueCount) skill\(queueCount == 1 ? "" : "s") queued")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let end = queueEndDate {
                        Spacer()
                        Text("Ends \(timeUntil(end))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func allianceFlourishRow(id: Int, name: String) -> some View {
        HStack(spacing: 8) {
            CachedAsyncImage(url: EVEImageURL.allianceLogo(id, size: 128)) { phase in
                if let image = phase.image {
                    image.resizable()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                }
            }
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "shield.lefthalf.filled")
                .font(.caption2)
                .foregroundStyle(.secondary.opacity(0.5))
        }
    }

    @ViewBuilder
    private var attributePillsRow: some View {
        if let attrs = liveAttributes {
            VStack(spacing: 8) {
                HStack(spacing: 5) {
                    ForEach(SkillTrainingAttribute.allCases) { attr in
                        AttributePill(
                            attr: attr,
                            value: attr.value(in: attrs),
                            isSelected: expandedAttr == attr,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedAttr = (expandedAttr == attr) ? nil : attr
                                }
                            }
                        )
                    }
                }

                if let focus = expandedAttr {
                    AttributeDetailPopover(
                        focus: focus,
                        attributes: attrs,
                        implantBonuses: liveImplantBonuses,
                        implantsResolved: liveImplantsResolved,
                        trainingSkillName: queueIsEmpty ? nil : queueSkillName,
                        trainingPrimary: liveTrainingPrimaryAttr,
                        trainingSecondary: liveTrainingSecondaryAttr,
                        onOpenRemapAdvisor: {
                            withAnimation(.easeInOut(duration: 0.15)) { expandedAttr = nil }
                            AppRouter.shared.pendingSection = .remapAdvisor
                        }
                    )
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(focus.color.opacity(0.25), lineWidth: 1))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        } else {
            HStack(spacing: 5) {
                let placeholders: [(String, LocalizedStringKey, Color)] = [("brain", "INT", Color.blue), ("memorychip", "MEM", Color.green), ("eye.fill", "PER", Color.orange), ("bolt.fill", "WIL", Color.purple), ("person.wave.2.fill", "CHA", Color.pink)]
                ForEach(placeholders, id: \.0) { icon, label, color in
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                        Text(label)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func cloneJumpRow(readyAt: Date) -> some View {
        let isReady = readyAt <= now
        HStack(spacing: 6) {
            Image(systemName: isReady ? "figure.walk.arrival" : "clock")
                .foregroundStyle(isReady ? .green : .orange)
                .font(.caption)
            Text(isReady ? "Clone jump available" : "Clone jump in \(timeUntil(readyAt))")
                .font(.caption)
                .foregroundStyle(isReady ? .green : .orange)
            Spacer()
        }
    }

    private func romanNumeral(_ level: Int) -> String {
        ["I", "II", "III", "IV", "V"][max(0, min(4, level - 1))]
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(now)
        if interval <= 0 { return "Done" }
        return EVEFormatters.formatDuration(Int(interval))
    }

    @ViewBuilder
    private var characterMetricsPanel: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
            spacing: 6
        ) {
            MetricTileView(
                icon: "creditcard.fill", color: .green,
                value: EVEFormatters.formatISKShort(summary?.wallet ?? 0),
                label: String(localized: "Wallet"),
                subLabel: dailyISKSubLabel
            )
            MetricTileView(
                icon: "brain.head.profile.fill", color: .cyan,
                value: formatSP(summary?.totalSP ?? 0),
                label: String(localized: "Skill Points")
            )
            trainingTile
            industryTile
            contractsTile
            piOrOnlineTile
        }
        .padding(10)
    }

    /// "Today" ISK made/spent (calendar day, resets at local midnight) shown under the Wallet tile.
    private var dailyISKSubLabel: String {
        guard let s = summary, s.dailyISKMade > 0 || s.dailyISKSpent > 0 else {
            return String(localized: "No ISK activity today")
        }
        return "+\(EVEFormatters.formatISKShort(s.dailyISKMade)) / -\(EVEFormatters.formatISKShort(s.dailyISKSpent)) today"
    }

    @ViewBuilder
    private var trainingTile: some View {
        if queueIsEmpty {
            MetricTileView(
                icon: "exclamationmark.triangle.fill", color: .orange,
                value: String(localized: "Queue empty"),
                label: String(localized: "Training"),
                isAlert: true
            )
        } else if let finish = queueSkillFinish {
            MetricTileView(
                icon: "graduationcap.fill", color: .blue,
                value: timeUntil(finish),
                label: queueSkillName ?? String(localized: "Training"),
                subLabel: "\(queueCount) in queue"
            )
        } else {
            MetricTileView(icon: "graduationcap.fill", color: .blue, value: String(localized: "Active"), label: String(localized: "Training"))
        }
    }

    @ViewBuilder
    private var industryTile: some View {
        if let s = summary, s.activeIndustryJobCount > 0 {
            MetricTileView(
                icon: "hammer.fill", color: .purple,
                value: "\(s.activeIndustryJobCount) active",
                label: String(localized: "Industry"),
                subLabel: s.nextJobFinish.map { timeUntil($0) }
            )
        } else {
            MetricTileView(icon: "hammer.fill", color: .secondary, value: String(localized: "None active"), label: String(localized: "Industry"))
        }
    }

    @ViewBuilder
    private var contractsTile: some View {
        if let s = summary, s.activeContractCount > 0 {
            MetricTileView(
                icon: "doc.text.fill", color: .teal,
                value: "\(s.activeContractCount) active",
                label: String(localized: "Contracts")
            )
        } else {
            MetricTileView(icon: "doc.text.fill", color: .secondary, value: String(localized: "None active"), label: String(localized: "Contracts"))
        }
    }

    @ViewBuilder
    private var piOrOnlineTile: some View {
        if let s = summary, s.colonyCount > 0 {
            if s.expiredExtractorCount > 0 {
                MetricTileView(
                    icon: "globe.americas.fill", color: .red,
                    value: "\(s.expiredExtractorCount) offline",
                    label: String(localized: "PI Extractors"),
                    isAlert: true
                )
            } else {
                MetricTileView(
                    icon: "globe.americas.fill", color: .mint,
                    value: "\(s.colonyCount) colon\(s.colonyCount == 1 ? "y" : "ies")",
                    label: String(localized: "Planetary Industry")
                )
            }
        } else {
            let isOnline = summary?.online == true
            MetricTileView(
                icon: "person.fill.checkmark", color: isOnline ? .blue : .secondary,
                value: isOnline ? String(localized: "Online") : String(localized: "Offline"),
                label: String(localized: "Status")
            )
        }
    }

    private var cardAccentColor: Color {
        guard let s = summary else { return Color(white: 0.25) }
        if s.loadError != nil { return .red }
        if s.expiredExtractorCount > 0 { return .red }
        if s.isQueueEmpty { return .orange }
        if s.online { return .green }
        return Color(white: 0.25)
    }

    @ViewBuilder
    private var onlineIndicator: some View {
        let isOnline = summary?.online == true
        HStack(spacing: 4) {
            ZStack {
                if isOnline {
                    Circle()
                        .fill(Color.green.opacity(0.35))
                        .frame(width: 16, height: 16)
                        .scaleEffect(pulsing ? 1.6 : 0.7)
                        .opacity(pulsing ? 0.0 : 0.5)
                        .animation(
                            .easeOut(duration: 0.9).repeatForever(autoreverses: false),
                            value: pulsing
                        )
                }
                Circle()
                    .fill(isOnline ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                    .shadow(color: isOnline ? .green.opacity(0.7) : .clear, radius: 4)
            }
            Text(isOnline ? "Online" : "Offline")
                .font(.caption2)
                .foregroundStyle(isOnline ? .green : .secondary)
        }
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
        liveSecurityStatus = charInfo.securityStatus
        liveBirthday = charInfo.birthday
        liveTitle = charInfo.title?.isEmpty == false ? charInfo.title : nil
        if let corpInfo: ESICorporationPublic = try? await ESIClient.shared.fetch(
            "/corporations/\(charInfo.corporationId)/"
        ) {
            liveCorpName = corpInfo.name
        }
        if let allianceId = charInfo.allianceId {
            liveAllianceID = allianceId
            if let allianceInfo: ESIAlliancePublic = try? await ESIClient.shared.fetch(
                "/alliances/\(allianceId)/"
            ) {
                liveAllianceName = allianceInfo.name
            }
        } else {
            liveAllianceName = nil
            liveAllianceID = nil
        }
        if let token = try? await accountManager.validToken(for: account) {
            let charID = account.characterID
            async let attrFetch: ESICharacterAttributes = ESIClient.shared.fetch(
                "/characters/\(charID)/attributes/", token: token
            )
            async let cloneFetch: ESIClonesResponse = ESIClient.shared.fetch(
                "/characters/\(charID)/clones/", token: token
            )
            async let implantFetch: [Int] = ESIClient.shared.fetch(
                "/characters/\(charID)/implants/", token: token
            )
            if let attrs = try? await attrFetch { liveAttributes = attrs }
            if let clones = try? await cloneFetch, let lastJump = clones.lastCloneJumpDate {
                liveCloneJumpReadyAt = lastJump.addingTimeInterval(24 * 3600)
            }
            if let implantIDs = try? await implantFetch {
                liveImplantBonuses = await resolveImplantAttributeBonuses(implantTypeIDs: implantIDs)
                liveImplantsResolved = true
            }
        }
    }

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
        .frame(height: 140)
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }
}
