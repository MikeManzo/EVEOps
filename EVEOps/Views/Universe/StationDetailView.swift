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

struct StationDetailView: View {
    let entry: StationEntry
    var onNavigateToMarket: (() -> Void)? = nil

    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @Environment(ThemeManager.self) private var themeManager

    @State private var stationType: ESIType?
    @State private var ownerName: String?
    @State private var jumpCount: Int?
    @State private var assetsAtStation: [StationAsset] = []
    @State private var autopilotMessage: String?
    @State private var isSettingAutopilot = false

    private var parts: StationNameParts {
        StationNameParts(stationName: entry.station.name, systemName: entry.systemName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                actionBar
                Divider()

                VStack(alignment: .leading, spacing: EVESpacing.xxl) {
                    locationSection
                    if !facilityStats.isEmpty { facilitiesSection }
                    let groups = StationService.grouped(entry.station.services)
                    if !groups.isEmpty { servicesSection(groups) }
                    if !assetsAtStation.isEmpty { assetsSection }
                }
                .padding(EVESpacing.xl)
            }
        }
        .background(.background)
        .task(id: entry.station.stationId) {
            // Reset state for new station
            autopilotMessage = nil
            jumpCount = nil
            assetsAtStation = []
            stationType = nil
            ownerName = entry.ownerName

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await loadDetails() }
                group.addTask { await loadJumpCount() }
                group.addTask { await loadAssetsAtStation() }
            }
        }
    }

    // MARK:  Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: EVEImageURL.typeRender(entry.station.typeId, size: 1024)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity)
                } else {
                    LinearGradient(
                        colors: [themeManager.palette.accent.opacity(0.35), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: EVESpacing.md + 2) {
                if let owner = entry.station.owner {
                    CachedAsyncImage(url: EVEImageURL.corporationLogo(owner, size: 128)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: EVERadius.md).fill(.white.opacity(0.1))
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: EVERadius.md))
                    .evePortraitRing(cornerRadius: EVERadius.md, accent: themeManager.palette.accent, lineWidth: 1)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
                    .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(parts.facility)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    HStack(spacing: EVESpacing.sm) {
                        EVESecurityBadge(status: entry.securityStatus, compact: true)
                        Text([entry.systemName, parts.orbit].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .padding(EVESpacing.lg)
        }
        .frame(height: 150)
        .clipped()
    }

    // MARK:  Action Bar

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: EVESpacing.sm) {
            HStack(spacing: EVESpacing.sm) {
                if let account = accountManager.selectedAccount, !account.isTokenExpired {
                    Button {
                        Task { await setAutopilot(clear: true) }
                    } label: {
                        Label("Set Destination", systemImage: "location.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(themeManager.palette.accent)
                    .disabled(isSettingAutopilot)

                    Button {
                        Task { await setAutopilot(clear: false) }
                    } label: {
                        Label("Waypoint", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSettingAutopilot)
                    .help("Add as waypoint")
                }

                Spacer(minLength: 0)

                if let onNavigateToMarket,
                   entry.station.services?.contains("market") == true {
                    Button(action: onNavigateToMarket) {
                        Image(systemName: "cart")
                    }
                    .buttonStyle(.bordered)
                    .help("Open Market Browser")
                    .accessibilityLabel("Open Market Browser")
                }
            }
            .controlSize(.small)

            if let msg = autopilotMessage {
                let ok = msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint")
                Label(msg, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(ok ? .green : .orange)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, EVESpacing.lg)
        .padding(.vertical, EVESpacing.md + 2)
        .animation(EVEMotion.snappy, value: autopilotMessage)
    }

    // MARK:  Location

    private var locationSection: some View {
        EVEInspectorSection("Location") {
            Grid(alignment: .leading, horizontalSpacing: EVESpacing.lg, verticalSpacing: EVESpacing.sm) {
                GridRow {
                    rowLabel("System")
                    HStack(spacing: EVESpacing.sm) {
                        Text(entry.systemName)
                            .eveContextMenu(.system(id: entry.systemId, name: entry.systemName))
                        EVESecurityBadge(status: entry.securityStatus, compact: true)
                    }
                }
                GridRow {
                    rowLabel("Constellation")
                    Text(entry.constellationName)
                }
                GridRow {
                    rowLabel("Distance")
                    distanceValue
                }
                if let ownerName {
                    GridRow {
                        rowLabel("Owner")
                        Text(ownerName)
                            .lineLimit(2)
                            .eveContextMenu(entry.station.owner.map { .corporation(id: $0, name: ownerName) })
                    }
                }
                if let typeName = stationType?.name {
                    GridRow {
                        rowLabel("Type")
                        Text(typeName).lineLimit(1)
                    }
                }
            }
            .font(.callout)
        }
    }

    @ViewBuilder
    private var distanceValue: some View {
        if let jumps = jumpCount {
            if jumps == 0 {
                Label("You are here", systemImage: "location.fill")
                    .foregroundStyle(themeManager.palette.accent)
            } else {
                Text("\(jumps) \(jumps == 1 ? "jump" : "jumps")").monospacedDigit()
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    private func rowLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    // MARK:  Facilities

    private struct FacilityStat: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
        let symbol: String
    }

    private var facilityStats: [FacilityStat] {
        var stats: [FacilityStat] = []
        let reprocessing = entry.station.services?.contains("reprocessing-plant") == true
        if reprocessing, let efficiency = entry.station.reprocessingEfficiency {
            stats.append(.init(id: "yield", label: "Reprocessing Yield",
                               value: efficiency.formatted(.percent.precision(.fractionLength(0))),
                               symbol: "arrow.3.trianglepath"))
        }
        if reprocessing, let take = entry.station.reprocessingStationsTake {
            stats.append(.init(id: "take", label: "Station Take",
                               value: take.formatted(.percent.precision(.fractionLength(1))),
                               symbol: "percent"))
        }
        if let cost = entry.station.officeRentalCost, cost > 0 {
            stats.append(.init(id: "office", label: "Office Rent / wk",
                               value: EVEFormatters.formatISKShort(cost),
                               symbol: "building.2"))
        }
        if let volume = entry.station.maxDockableShipVolume, volume > 0 {
            stats.append(.init(id: "dock", label: "Max Dockable",
                               value: volume.formatted(.number.notation(.compactName)) + " m³",
                               symbol: "arrow.down.to.line"))
        }
        return stats
    }

    private var facilitiesSection: some View {
        EVEInspectorSection("Facilities") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: EVESpacing.sm), GridItem(.flexible())],
                      spacing: EVESpacing.sm) {
                ForEach(facilityStats) { stat in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(stat.label, systemImage: stat.symbol)
                            .font(.eveLabel)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Text(stat.value)
                            .font(.eveStatCompact)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(EVESpacing.md + 2)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.md))
                }
            }
        }
    }

    // MARK:  Services

    private func servicesSection(_ groups: [(category: StationService.Category, services: [StationService])]) -> some View {
        EVEInspectorSection("Services") {
            VStack(alignment: .leading, spacing: EVESpacing.md + 2) {
                ForEach(groups, id: \.category) { group in
                    VStack(alignment: .leading, spacing: EVESpacing.xs + 1) {
                        Text(group.category.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                                  alignment: .leading, spacing: EVESpacing.xs + 1) {
                            ForEach(group.services) { service in
                                Label {
                                    Text(service.label)
                                } icon: {
                                    Image(systemName: service.symbol)
                                        .foregroundStyle(themeManager.palette.accent)
                                        .frame(width: 16)
                                }
                                .font(.callout)
                                .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK:  Assets At Station

    private var assetsSection: some View {
        EVEInspectorSection("Your Assets Here") {
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                ForEach(assetsAtStation.prefix(8)) { asset in
                    HStack(spacing: EVESpacing.md) {
                        CachedAsyncImage(url: EVEImageURL.typeIcon(asset.typeId, size: 64)) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                        }
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))
                        Text(asset.typeName)
                            .font(.callout)
                            .lineLimit(1)
                        if asset.isBlueprintCopy {
                            Text("BPC")
                                .font(.eveMicroBold)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, EVESpacing.xs)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: EVERadius.xs))
                        }
                        Spacer()
                        Text(asset.quantity, format: .number)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .eveContextMenu(.item(typeID: asset.typeId, name: asset.typeName))
                }
                if assetsAtStation.count > 8 {
                    Text("and \(assetsAtStation.count - 8) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK:  Autopilot

    private func setAutopilot(clear: Bool) async {
        guard let account = accountManager.selectedAccount else { return }
        isSettingAutopilot = true
        autopilotMessage = nil
        do {
            let token = try await accountManager.validToken(for: account)
            try await ESIClient.shared.postAction(
                "/ui/autopilot/waypoint/",
                token: token,
                queryItems: [
                    URLQueryItem(name: "add_to_beginning", value: "false"),
                    URLQueryItem(name: "clear_other_waypoints", value: clear ? "true" : "false"),
                    URLQueryItem(name: "destination_id", value: "\(entry.station.stationId)")
                ]
            )
            autopilotMessage = clear ? "Destination set in EVE client." : "Waypoint added in EVE client."
        } catch ESIError.unauthorized {
            autopilotMessage = "Needs esi-ui.write_waypoint.v1 scope."
        } catch {
            autopilotMessage = error.localizedDescription
        }
        isSettingAutopilot = false
    }

    // MARK:  Data Loading

    private func loadDetails() async {
        async let typeTask = UniverseCache.shared.type(id: entry.station.typeId)
        async let ownerTask: String? = {
            guard let ownerId = entry.station.owner else { return nil }
            let names = await NameResolver.shared.resolve(ids: [ownerId])
            return names[ownerId]
        }()

        let (type, owner) = await (typeTask, ownerTask)
        stationType = type
        ownerName = owner ?? ownerName
    }

    private func loadJumpCount() async {
        guard let account = accountManager.selectedAccount,
              let data = prefetcher.data(for: account.characterID) else { return }
        let originSystemId = data.location.solarSystemId
        if originSystemId == entry.systemId {
            jumpCount = 0
            return
        }
        do {
            let route: [Int] = try await ESIClient.shared.fetch(
                "/route/\(originSystemId)/\(entry.systemId)/",
                queryItems: [URLQueryItem(name: "flag", value: "shortest")]
            )
            jumpCount = max(0, route.count - 1)
        } catch {
            // No route or unreachable — leave nil
        }
    }

    private func loadAssetsAtStation() async {
        guard let account = accountManager.selectedAccount, !account.isTokenExpired else { return }
        do {
            let token = try await accountManager.validToken(for: account)
            let rawAssets: [ESIAsset] = try await ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/assets/", token: token
            )
            let atStation = rawAssets.filter {
                $0.locationId == entry.station.stationId && $0.locationType == "station"
            }
            guard !atStation.isEmpty else { return }

            let typeIds = Array(Set(atStation.map(\.typeId)))
            let typeNames = await NameResolver.shared.resolve(ids: typeIds)

            // Aggregate quantity by typeId
            var byType: [Int: (name: String, qty: Int, isBPC: Bool)] = [:]
            for asset in atStation {
                let name = typeNames[asset.typeId] ?? "Unknown Type"
                let isBPC = asset.isBlueprintCopy ?? false
                if let existing = byType[asset.typeId] {
                    byType[asset.typeId] = (existing.name, existing.qty + asset.quantity, existing.isBPC || isBPC)
                } else {
                    byType[asset.typeId] = (name, asset.quantity, isBPC)
                }
            }
            assetsAtStation = byType.map { typeId, info in
                StationAsset(typeId: typeId, typeName: info.name, quantity: info.qty, isBlueprintCopy: info.isBPC)
            }.sorted { $0.typeName < $1.typeName }
        } catch {
            // Silently fail — assets are optional context
        }
    }
}

// MARK:  Supporting Types

private struct StationAsset: Identifiable {
    let typeId: Int
    let typeName: String
    let quantity: Int
    let isBlueprintCopy: Bool
    var id: Int { typeId }
}
