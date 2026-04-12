import SwiftUI

struct LocationOverviewView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var locations: [CharacterLocationInfo] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: locations.isEmpty, emptyMessage: "No location data") {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(locations, id: \.characterID) { info in
                        locationCard(info)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Location Overview")
        .task { await loadLocations() }
    }

    // MARK: - Location Card

    private func locationCard(_ info: CharacterLocationInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Ship render banner
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: EVEImageURL.typeRender(info.shipTypeId, size: 1024)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(height: 140)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(white: 0.1))
                            .frame(height: 140)
                    }
                }

                // Gradient overlay for readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .frame(maxHeight: .infinity, alignment: .bottom)

                // Character identity overlay
                HStack(spacing: 10) {
                    AsyncImage(url: EVEImageURL.characterPortrait(info.characterID, size: 256)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(info.isOnline ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(info.characterName)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        Text(info.corporationName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Spacer()

                    // Online status badge
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(info.isOnline ? "Online" : "Offline")
                            .font(.caption.bold())
                            .foregroundStyle(info.isOnline ? .green : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (info.isOnline ? Color.green : Color.gray).opacity(0.2),
                                in: Capsule()
                            )
                        if let logins = info.loginCount {
                            Text("\(logins) logins")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {
                // Location details
                HStack(alignment: .top, spacing: 20) {
                    // System / Region info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "location.fill")
                                .foregroundStyle(.blue)
                            Text("Location")
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            // Solar system with security
                            HStack(spacing: 6) {
                                Text(info.systemName)
                                    .font(.body.bold())
                                securityBadge(info.securityValue)
                            }

                            // Constellation
                            if let constellation = info.constellationName {
                                infoRow(label: "Constellation", value: constellation)
                            }

                            // Region
                            if let region = info.regionName {
                                infoRow(label: "Region", value: region)
                            }

                            // Docked location
                            if let docked = info.dockedAt {
                                HStack(spacing: 4) {
                                    Image(systemName: "building.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                    Text(docked)
                                        .font(.caption)
                                        .foregroundStyle(.teal)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "airplane")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    Text("In space")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 100)

                    // Ship info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "airplane")
                                .foregroundStyle(.purple)
                            Text("Ship")
                                .font(.subheadline.bold())
                        }

                        HStack(spacing: 10) {
                            AsyncImage(url: EVEImageURL.typeIcon(info.shipTypeId, size: 256)) { phase in
                                if let image = phase.image {
                                    image.resizable()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                } else {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(.quaternary)
                                        .frame(width: 48, height: 48)
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(info.shipName)
                                    .font(.body.bold())
                                    .lineLimit(1)
                                Text(info.shipTypeName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let group = info.shipGroupName {
                                    Text(group)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        // Ship attributes
                        if info.shipMass != nil || info.shipVolume != nil || info.shipCapacity != nil {
                            HStack(spacing: 12) {
                                if let mass = info.shipMass, mass > 0 {
                                    shipStat(label: "Mass", value: formatLarge(mass) + " kg")
                                }
                                if let volume = info.shipVolume, volume > 0 {
                                    shipStat(label: "Volume", value: String(format: "%.0f m\u{00B3}", volume))
                                }
                                if let capacity = info.shipCapacity, capacity > 0 {
                                    shipStat(label: "Cargo", value: String(format: "%.0f m\u{00B3}", capacity))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Login/Logout times
                if info.lastLogin != nil || info.lastLogout != nil {
                    Divider()

                    HStack(spacing: 20) {
                        if let login = info.lastLogin {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last Login")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(EVEFormatters.dateFormatter.string(from: login))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(login, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        if let logout = info.lastLogout {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last Logout")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(EVEFormatters.dateFormatter.string(from: logout))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(logout, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if let logins = info.loginCount {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Total Logins")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("\(logins)")
                                    .font(.caption.bold().monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func securityBadge(_ value: Double) -> some View {
        Text(String(format: "%.1f", value))
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(securityColor(value))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(securityColor(value).opacity(0.15), in: Capsule())
    }

    private func securityColor(_ value: Double) -> Color {
        switch value {
        case 0.9...: return .cyan
        case 0.7..<0.9: return .green
        case 0.5..<0.7: return .yellow
        case 0.3..<0.5: return .orange
        case 0.1..<0.3: return Color(red: 1, green: 0.5, blue: 0)
        default: return .red
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func shipStat(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func formatLarge(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }

    // MARK: - Data Loading

    private func loadLocations() async {
        isLoading = true
        var data: [CharacterLocationInfo] = []
        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)

                async let fetchLocation: ESICharacterLocation = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/location/", token: token
                )
                async let fetchShip: ESICharacterShip = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/ship/", token: token
                )
                async let fetchOnline: ESICharacterOnline = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/online/", token: token
                )

                let (location, ship, online) = try await (fetchLocation, fetchShip, fetchOnline)

                // System → Constellation → Region chain
                let systemInfo: ESISolarSystem = try await ESIClient.shared.fetch(
                    "/universe/systems/\(location.solarSystemId)/"
                )

                async let fetchConstellation: ESIConstellation = ESIClient.shared.fetch(
                    "/universe/constellations/\(systemInfo.constellationId)/"
                )
                async let fetchShipType: ESIType = ESIClient.shared.fetch(
                    "/universe/types/\(ship.shipTypeId)/"
                )

                let (constellation, shipType) = try await (fetchConstellation, fetchShipType)

                let region: ESIRegion? = try? await ESIClient.shared.fetch(
                    "/universe/regions/\(constellation.regionId)/"
                )

                // Ship group name
                let shipGroup: ESIGroup? = try? await ESIClient.shared.fetch(
                    "/universe/groups/\(shipType.groupId)/"
                )

                // Docked location
                var dockedAt: String?
                if let stationId = location.stationId {
                    let station: ESIStation = try await ESIClient.shared.fetch(
                        "/universe/stations/\(stationId)/"
                    )
                    dockedAt = station.name
                } else if let structureId = location.structureId {
                    if let structure: ESIStructure = try? await ESIClient.shared.fetch(
                        "/universe/structures/\(structureId)/", token: token
                    ) {
                        dockedAt = structure.name
                    } else {
                        dockedAt = "Player Structure"
                    }
                }

                data.append(CharacterLocationInfo(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    corporationName: account.corporationName,
                    isOnline: online.online,
                    lastLogin: online.lastLogin,
                    lastLogout: online.lastLogout,
                    loginCount: online.logins,
                    systemName: systemInfo.name,
                    securityValue: systemInfo.securityStatus,
                    constellationName: constellation.name,
                    regionName: region?.name,
                    dockedAt: dockedAt,
                    shipName: ship.shipName,
                    shipTypeName: shipType.name,
                    shipTypeId: ship.shipTypeId,
                    shipGroupName: shipGroup?.name,
                    shipMass: shipType.mass,
                    shipVolume: shipType.volume,
                    shipCapacity: shipType.capacity
                ))
            } catch {
                // Skip
            }
        }
        locations = data
        isLoading = false
    }
}

// MARK: - Data Model

struct CharacterLocationInfo {
    let characterID: Int
    let characterName: String
    let corporationName: String
    let isOnline: Bool
    let lastLogin: Date?
    let lastLogout: Date?
    let loginCount: Int?
    let systemName: String
    let securityValue: Double
    let constellationName: String?
    let regionName: String?
    let dockedAt: String?
    let shipName: String
    let shipTypeName: String
    let shipTypeId: Int
    let shipGroupName: String?
    let shipMass: Double?
    let shipVolume: Double?
    let shipCapacity: Double?
}
