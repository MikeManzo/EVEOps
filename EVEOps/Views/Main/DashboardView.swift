import SwiftUI

struct DashboardView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher
    @State private var summaries: [CharacterSummary] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Dashboard")
                    .font(.largeTitle.bold())
                    .padding(.horizontal)

                // Aggregate summary bar
                if !summaries.isEmpty {
                    SummaryBarView(summaries: summaries)
                        .padding(.horizontal)
                }

                // Per-character cards
                let columns = [GridItem(.adaptive(minimum: 340, maximum: 480), spacing: 16)]
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(accountManager.accounts, id: \.characterID) { account in
                        CharacterCardView(
                            account: account,
                            summary: summaries.first { $0.characterID == account.characterID }
                        )
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .overlay {
            if isLoading && summaries.isEmpty {
                ProgressView("Loading dashboard...")
            }
        }
        .task { await loadAllSummaries() }
    }

    private func loadAllSummaries() async {
        isLoading = true
        await withTaskGroup(of: CharacterSummary.self) { group in
            for account in accountManager.accounts {
                group.addTask {
                    await self.loadSummary(for: account)
                }
            }
            for await summary in group {
                summaries.removeAll { $0.characterID == summary.characterID }
                summaries.append(summary)
            }
        }
        isLoading = false
    }

    private func loadSummary(for account: StoredAccount) async -> CharacterSummary {
        var summary = CharacterSummary(characterID: account.characterID)

        // Try prefetched data first
        if let prefetched = prefetcher.data(for: account.characterID) {
            return await buildSummary(from: prefetched, for: account)
        }

        // Fallback to fetching directly
        do {
            let token = try await accountManager.validToken(for: account)

            async let fetchWallet: Double = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/wallet/", token: token
            )
            async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/skillqueue/", token: token
            )
            async let fetchSkills: ESISkillsResponse = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/skills/", token: token
            )
            async let fetchLocation: ESICharacterLocation = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/location/", token: token
            )
            async let fetchShip: ESICharacterShip = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/ship/", token: token
            )
            async let fetchOnline: ESICharacterOnline = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/online/", token: token
            )
            async let fetchContracts: [ESIContract] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/contracts/", token: token
            )
            async let fetchIndustry: [ESIIndustryJob] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/industry/jobs/", token: token
            )
            async let fetchColonies: [ESIColony] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/planets/", token: token
            )

            let (wallet, queue, skills, loc, ship, online, contracts, industry, colonies) = try await (
                fetchWallet, fetchQueue, fetchSkills, fetchLocation, fetchShip, fetchOnline,
                fetchContracts, fetchIndustry, fetchColonies
            )

            summary.wallet = wallet
            summary.totalSP = skills.totalSp
            summary.online = online.online
            summary.ship = ship
            summary.location = loc

            // Skill queue
            let activeQueue = queue.filter { $0.finishDate ?? .distantPast > Date() }
            summary.skillQueueCount = activeQueue.count
            summary.currentSkillFinish = activeQueue.first?.finishDate
            summary.queueEnd = activeQueue.last?.finishDate
            if let first = activeQueue.first {
                summary.trainingSkillID = first.skillId
            }
            summary.isQueueEmpty = activeQueue.isEmpty

            // Contracts
            let activeContracts = contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }
            summary.activeContractCount = activeContracts.count

            // Industry
            let activeJobs = industry.filter { $0.status == "active" }
            summary.activeIndustryJobCount = activeJobs.count
            summary.nextJobFinish = activeJobs.map(\.endDate).min()

            // PI colonies
            summary.colonyCount = colonies.count
            for colony in colonies {
                do {
                    let layout: ESIColonyLayout = try await ESIClient.shared.fetch(
                        "/characters/\(account.characterID)/planets/\(colony.planetId)/", token: token
                    )
                    let expiredExtractors = layout.pins.filter { pin in
                        pin.extractorDetails != nil && (pin.expiryTime ?? .distantPast) < Date()
                    }
                    summary.expiredExtractorCount += expiredExtractors.count
                } catch {}
            }

            // Resolve system name via UniverseCache
            if let sysInfo = await UniverseCache.shared.solarSystem(id: loc.solarSystemId) {
                summary.systemName = sysInfo.name
                summary.securityStatus = sysInfo.securityStatus
            }

            // Resolve ship type name via UniverseCache
            if let typeInfo = await UniverseCache.shared.type(id: ship.shipTypeId) {
                summary.shipTypeName = typeInfo.name
            }

            // Resolve training skill name
            if let skillID = summary.trainingSkillID {
                let resolved = await NameResolver.shared.resolve(ids: [skillID])
                summary.trainingSkillName = resolved[skillID]
            }
        } catch {
            // Partial data is fine
        }
        return summary
    }

    /// Build a summary from prefetched data, only fetching universe lookups
    private nonisolated func buildSummary(from prefetched: DashboardPrefetcher.PrefetchedCharacterData, for account: StoredAccount) async -> CharacterSummary {
        var summary = CharacterSummary(characterID: account.characterID)
        summary.wallet = prefetched.wallet
        summary.totalSP = prefetched.skills.totalSp
        summary.online = prefetched.online.online
        summary.ship = prefetched.ship
        summary.location = prefetched.location

        let activeQueue = prefetched.skillQueue.filter { $0.finishDate ?? .distantPast > Date() }
        summary.skillQueueCount = activeQueue.count
        summary.currentSkillFinish = activeQueue.first?.finishDate
        summary.queueEnd = activeQueue.last?.finishDate
        if let first = activeQueue.first {
            summary.trainingSkillID = first.skillId
        }
        summary.isQueueEmpty = activeQueue.isEmpty

        let activeContracts = prefetched.contracts.filter { $0.status == "outstanding" || $0.status == "in_progress" }
        summary.activeContractCount = activeContracts.count

        let activeJobs = prefetched.industryJobs.filter { $0.status == "active" }
        summary.activeIndustryJobCount = activeJobs.count
        summary.nextJobFinish = activeJobs.map(\.endDate).min()

        summary.colonyCount = prefetched.colonies.count

        // PI extractor check still needs individual fetches
        if !prefetched.colonies.isEmpty {
            if let token = try? await AccountManager.tokenForAccount(account) {
                for colony in prefetched.colonies {
                    if let layout: ESIColonyLayout = try? await ESIClient.shared.fetch(
                        "/characters/\(account.characterID)/planets/\(colony.planetId)/", token: token
                    ) {
                        let expired = layout.pins.filter { $0.extractorDetails != nil && ($0.expiryTime ?? .distantPast) < Date() }
                        summary.expiredExtractorCount += expired.count
                    }
                }
            }
        }

        // Universe lookups (likely cached on disk already)
        if let sysInfo = await UniverseCache.shared.solarSystem(id: prefetched.location.solarSystemId) {
            summary.systemName = sysInfo.name
            summary.securityStatus = sysInfo.securityStatus
        }
        if let typeInfo = await UniverseCache.shared.type(id: prefetched.ship.shipTypeId) {
            summary.shipTypeName = typeInfo.name
        }
        if let skillID = summary.trainingSkillID {
            let resolved = await NameResolver.shared.resolve(ids: [skillID])
            summary.trainingSkillName = resolved[skillID]
        }

        return summary
    }
}

// MARK: - Summary Data

struct CharacterSummary {
    let characterID: Int
    var wallet: Double = 0
    var totalSP: Int = 0
    var online: Bool = false
    var ship: ESICharacterShip?
    var shipTypeName: String = ""
    var location: ESICharacterLocation?
    var systemName: String = ""
    var securityStatus: Double?
    var skillQueueCount: Int = 0
    var currentSkillFinish: Date?
    var queueEnd: Date?
    var trainingSkillID: Int?
    var trainingSkillName: String?
    var isQueueEmpty: Bool = true
    var activeContractCount: Int = 0
    var activeIndustryJobCount: Int = 0
    var nextJobFinish: Date?
    var colonyCount: Int = 0
    var expiredExtractorCount: Int = 0
}

// MARK: - Aggregate Summary Bar

struct SummaryBarView: View {
    let summaries: [CharacterSummary]

    private var totalWealth: Double { summaries.reduce(0) { $0 + $1.wallet } }
    private var totalSP: Int { summaries.reduce(0) { $0 + $1.totalSP } }
    private var emptyQueues: Int { summaries.filter(\.isQueueEmpty).count }
    private var activeJobs: Int { summaries.reduce(0) { $0 + $1.activeIndustryJobCount } }
    private var activeContracts: Int { summaries.reduce(0) { $0 + $1.activeContractCount } }
    private var expiredExtractors: Int { summaries.reduce(0) { $0 + $1.expiredExtractorCount } }
    private var onlineCount: Int { summaries.filter(\.online).count }

    var body: some View {
        HStack(spacing: 0) {
            summaryTile(icon: "creditcard.fill", color: .green, label: "Total Wealth",
                        value: EVEFormatters.formatISKShort(totalWealth))

            Divider().frame(height: 36)

            summaryTile(icon: "brain.head.profile.fill", color: .cyan, label: "Total SP",
                        value: formatSP(totalSP))

            Divider().frame(height: 36)

            summaryTile(icon: "person.fill.checkmark", color: .blue, label: "Online",
                        value: "\(onlineCount) / \(summaries.count)")

            Divider().frame(height: 36)

            summaryTile(icon: "graduationcap.fill",
                        color: emptyQueues > 0 ? .orange : .green,
                        label: "Training",
                        value: emptyQueues > 0 ? "\(emptyQueues) empty" : "All active")

            Divider().frame(height: 36)

            summaryTile(icon: "hammer.fill", color: .purple, label: "Industry",
                        value: "\(activeJobs) active")

            Divider().frame(height: 36)

            summaryTile(icon: "doc.text.fill", color: .teal, label: "Contracts",
                        value: "\(activeContracts) active")

            if expiredExtractors > 0 {
                Divider().frame(height: 36)
                summaryTile(icon: "exclamationmark.triangle.fill", color: .red, label: "PI Alerts",
                            value: "\(expiredExtractors) offline")
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func summaryTile(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM", Double(sp) / 1_000_000)
        } else if sp >= 1_000 {
            return String(format: "%.0fK", Double(sp) / 1_000)
        }
        return "\(sp)"
    }
}

// MARK: - Character Card

struct CharacterCardView: View {
    let account: StoredAccount
    let summary: CharacterSummary?

    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        VStack(spacing: 0) {
            // Ship render banner with corp logo overlay
            ZStack(alignment: .bottomTrailing) {
                if let ship = summary?.ship {
                    AsyncImage(url: EVEImageURL.typeRender(ship.shipTypeId, size: 1024)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 120)
                                .clipped()
                        default:
                            bannerPlaceholder
                        }
                    }
                } else {
                    bannerPlaceholder
                }

                AsyncImage(url: EVEImageURL.corporationLogo(account.corporationID, size: 256)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .shadow(color: .black.opacity(0.5), radius: 3)
                    }
                }
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 10) {
                // Character identity row
                HStack(spacing: 12) {
                    AsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 512)) { image in
                        image.resizable()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(account.characterName)
                                .font(.headline)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(summary?.online == true ? .green : .gray)
                                    .frame(width: 8, height: 8)
                                Text(summary?.online == true ? "Online" : "Offline")
                                    .font(.caption2)
                                    .foregroundStyle(summary?.online == true ? .green : .secondary)
                            }
                        }
                        Text(account.corporationName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let allianceName = account.allianceName {
                            Text(allianceName)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
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
                            if let sec = summary?.securityStatus {
                                Text(String(format: "%.1f", sec))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(sec >= 0.5 ? .green : sec >= 0.0 ? .yellow : .red)
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if let ship = summary?.ship {
                            AsyncImage(url: EVEImageURL.typeIcon(ship.shipTypeId, size: 256)) { phase in
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

                // Skill queue
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
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var skillQueueRow: some View {
        if let s = summary {
            if s.isQueueEmpty {
                Label {
                    Text("Queue empty!")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(s.trainingSkillName ?? "Training...")
                                .font(.caption)
                                .lineLimit(1)
                            if let finish = s.currentSkillFinish {
                                Spacer()
                                Text(EVEFormatters.timeUntil(finish))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 4) {
                            Text("\(s.skillQueueCount) skill\(s.skillQueueCount == 1 ? "" : "s") in queue")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            if let end = s.queueEnd {
                                Spacer()
                                Text("Ends: \(EVEFormatters.timeUntil(end))")
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
    }

    private var bannerPlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.12))
            .frame(height: 120)
            .overlay {
                if summary == nil {
                    ProgressView().scaleEffect(0.7)
                }
            }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 {
            return String(format: "%.1fM SP", Double(sp) / 1_000_000)
        } else if sp >= 1_000 {
            return String(format: "%.0fK SP", Double(sp) / 1_000)
        }
        return "\(sp) SP"
    }
}
