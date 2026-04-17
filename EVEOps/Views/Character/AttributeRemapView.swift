import SwiftUI
import Charts

// Dogma attribute IDs for skill training attributes
private let kPrimaryAttrID = 180
private let kSecondaryAttrID = 181
private let attrIDToKey: [Int: String] = [
    164: "intelligence", 165: "charisma", 166: "memory",
    167: "perception", 168: "willpower"
]

struct AttributeRemapView: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    @State private var characterData: [CharacterRemapData] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedCharacterID: Int?
    @State private var now = Date()

    private var selectedData: CharacterRemapData? {
        if let id = selectedCharacterID {
            return characterData.first { $0.characterID == id }
        }
        return characterData.first
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error,
                         isEmpty: characterData.isEmpty, emptyMessage: "No training data") {
            ScrollView {
                VStack(spacing: 20) {
                    if characterData.count > 1 {
                        Picker("Character", selection: $selectedCharacterID) {
                            ForEach(characterData, id: \.characterID) { d in
                                Text(d.characterName).tag(Optional(d.characterID))
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 500)
                    }

                    if let data = selectedData {
                        remapStatusCard(data)
                        attributesCard(data)
                        if !data.queuePairs.isEmpty {
                            queueDemandCard(data)
                            recommendationCard(data)
                        }
                        trainingSpeedCard(data)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Remap Advisor")
        .task(id: accountManager.selectedCharacterID) { await load() }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }

    // MARK: - Remap Status

    private func remapStatusCard(_ data: CharacterRemapData) -> some View {
        HStack(spacing: 16) {
            // Bonus remaps
            VStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .foregroundStyle(data.bonusRemaps > 0 ? .green : .secondary)
                Text("\(data.bonusRemaps)")
                    .font(.title.bold())
                    .foregroundStyle(data.bonusRemaps > 0 ? .green : .primary)
                Text("Bonus Remaps")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Annual remap cooldown
            VStack(spacing: 4) {
                if let cooldown = data.nextAnnualRemap {
                    if cooldown > now {
                        Image(systemName: "clock.fill").font(.title2).foregroundStyle(.orange)
                        Text(timeUntil(cooldown)).font(.title3.bold().monospacedDigit()).foregroundStyle(.orange)
                        Text("Until Annual Remap").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                        Text("Available").font(.title3.bold()).foregroundStyle(.green)
                        Text("Annual Remap").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    Text("Available").font(.title3.bold()).foregroundStyle(.green)
                    Text("Annual Remap").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Last remap
            if let lastRemap = data.lastRemapDate {
                VStack(spacing: 4) {
                    Image(systemName: "calendar").font(.title2).foregroundStyle(.secondary)
                    Text(EVEFormatters.dateFormatter.string(from: lastRemap))
                        .font(.caption.bold().monospacedDigit())
                    Text("Last Remap").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Attributes Card

    private func attributesCard(_ data: CharacterRemapData) -> some View {
        let attrs = data.attributes
        let attrList: [(String, Int, Color)] = [
            ("Intelligence", attrs.intelligence, .blue),
            ("Memory",       attrs.memory,       .cyan),
            ("Perception",   attrs.perception,   .green),
            ("Willpower",    attrs.willpower,    .orange),
            ("Charisma",     attrs.charisma,     .pink)
        ]
        let maxVal = attrList.map(\.1).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text("Current Attributes")
                .font(.headline)
            Text("Values include implant bonuses. Remapping only changes base attribute points.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(attrList, id: \.0) { name, value, color in
                HStack(spacing: 10) {
                    Text(name)
                        .font(.subheadline)
                        .frame(width: 110, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                                .frame(width: geo.size.width * Double(value) / Double(maxVal + 5))
                        }
                    }
                    .frame(height: 16)
                    Text("\(value)")
                        .font(.subheadline.bold().monospacedDigit())
                        .frame(width: 32, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Queue Demand Card

    private func queueDemandCard(_ data: CharacterRemapData) -> some View {
        let pairs = data.queuePairs.sorted { $0.value > $1.value }
        let totalSP = pairs.reduce(0) { $0 + $1.value }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Queue Attribute Demand")
                .font(.headline)
            Text("SP distribution across training attribute pairs in your current queue.")
                .font(.caption).foregroundStyle(.secondary)

            if totalSP > 0 {
                ForEach(pairs.prefix(5), id: \.key) { pair, sp in
                    let fraction = Double(sp) / Double(totalSP)
                    let (primary, secondary) = splitPair(pair)
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(primary) / \(secondary)")
                                .font(.subheadline)
                            Text(formatSP(sp))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .frame(width: 180, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(pairColor(pair))
                                    .frame(width: geo.size.width * fraction)
                            }
                        }
                        .frame(height: 14)
                        Text("\(Int(fraction * 100))%")
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                    }
                }

                if let dominant = pairs.first, let _ = pairs.second {
                    let (p, s) = splitPair(dominant.key)
                    let currentP = attributeValue(data.attributes, name: p)
                    let currentS = attributeValue(data.attributes, name: s)
                    let currentRate = currentP + currentS / 2

                    Divider()
                    HStack(spacing: 8) {
                        Image(systemName: dominant.value > (totalSP / 2) ? "lightbulb.fill" : "lightbulb")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your queue is \(Int(Double(dominant.value) / Double(totalSP) * 100))% **\(p)/\(s)** skills.")
                                .font(.caption)
                            Text("Current speed: \(currentRate) SP/min • \(currentRate * 60) SP/hr")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("Queue is empty — nothing to analyze.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Training Speed Card

    private func trainingSpeedCard(_ data: CharacterRemapData) -> some View {
        let attrs = data.attributes
        let speeds: [(String, String, Int)] = [
            ("Int / Mem", "Intelligence + Memory",
             attrs.intelligence + attrs.memory / 2),
            ("Per / Wil", "Perception + Willpower",
             attrs.perception + attrs.willpower / 2),
            ("Wil / Per", "Willpower + Perception",
             attrs.willpower + attrs.perception / 2),
            ("Int / Cha", "Intelligence + Charisma",
             attrs.intelligence + attrs.charisma / 2),
            ("Mem / Int", "Memory + Intelligence",
             attrs.memory + attrs.intelligence / 2),
            ("Cha / Mem", "Charisma + Memory",
             attrs.charisma + attrs.memory / 2),
        ]
        let best = speeds.map(\.2).max() ?? 1

        return VStack(alignment: .leading, spacing: 12) {
            Text("Training Speed by Attribute Pair")
                .font(.headline)
            Text("SP per minute = primary + floor(secondary ÷ 2). Higher is faster.")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(speeds.sorted { $0.2 > $1.2 }, id: \.0) { short, long, rate in
                HStack(spacing: 10) {
                    Text(long)
                        .font(.subheadline)
                        .frame(width: 210, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(rate == best ? Color.green : Color.blue.opacity(0.6))
                                .frame(width: geo.size.width * Double(rate) / Double(best))
                        }
                    }
                    .frame(height: 14)
                    Text("\(rate) SP/min")
                        .font(.caption.monospacedDigit())
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Recommendation Card

    /// EVE remap pool: 5 attributes × min 17 + 14 free points = 99 total.
    /// Optimal for one pair: put 10 into primary (→ 27), 4 into secondary (→ 21), rest stay at 17.
    private func recommendationCard(_ data: CharacterRemapData) -> some View {
        let pairs = data.queuePairs.sorted { $0.value > $1.value }
        guard let dominant = pairs.first else { return AnyView(EmptyView()) }

        let totalSP = pairs.reduce(0) { $0 + $1.value }
        let dominantPct = Int(Double(dominant.value) / Double(max(totalSP, 1)) * 100)
        let (primary, secondary) = splitPair(dominant.key)

        // Recommended base values after optimal remap for this pair
        let recommended: [(String, Int, Color)] = [
            ("Intelligence", primary == "Intelligence" ? 27 : secondary == "Intelligence" ? 21 : 17, .blue),
            ("Memory",       primary == "Memory"       ? 27 : secondary == "Memory"       ? 21 : 17, .cyan),
            ("Perception",   primary == "Perception"   ? 27 : secondary == "Perception"   ? 21 : 17, .green),
            ("Willpower",    primary == "Willpower"    ? 27 : secondary == "Willpower"    ? 21 : 17, .orange),
            ("Charisma",     primary == "Charisma"     ? 27 : secondary == "Charisma"     ? 21 : 17, .pink),
        ]

        let remapReady = data.bonusRemaps > 0
            || data.nextAnnualRemap == nil
            || (data.nextAnnualRemap.map { $0 <= now } ?? false)

        // Current speed for the dominant pair (includes implant bonuses in current attrs)
        let curPrimary = attributeValue(data.attributes, name: primary)
        let curSecondary = attributeValue(data.attributes, name: secondary)
        let currentSpeed = curPrimary + curSecondary / 2

        // Optimal base speed (no implants considered)
        let optimalSpeed = 27 + 21 / 2  // = 37

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: remapReady ? "checkmark.circle.fill" : "clock.fill")
                        .foregroundStyle(remapReady ? .green : .orange)
                    Text(remapReady ? "Remap Available — Recommendation" : "Remap on Cooldown — Planned Recommendation")
                        .font(.headline)
                }

                // Summary sentence
                Text("Your queue is **\(dominantPct)% \(primary) / \(secondary)** skills. For fastest training, remap to:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Recommended values table
                VStack(spacing: 6) {
                    ForEach(recommended, id: \.0) { name, value, color in
                        HStack(spacing: 8) {
                            Text(name)
                                .font(.subheadline)
                                .frame(width: 110, alignment: .trailing)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(value > 17 ? color : Color.secondary.opacity(0.3))
                                    .frame(width: max(1, CGFloat(value - 17) / 10.0) * 120)
                            }
                            .frame(width: 120, height: 14)
                            Text("\(value)")
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(width: 28, alignment: .trailing)
                                .foregroundStyle(value == 27 ? color : value == 21 ? color.opacity(0.7) : .secondary)
                            Text(value == 27 ? "Primary" : value == 21 ? "Secondary" : "Min")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 60, alignment: .leading)
                        }
                    }
                }

                Divider()

                // Speed comparison
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text("Current speed")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(currentSpeed) SP/min")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    VStack(spacing: 2) {
                        Text("Optimal base")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(optimalSpeed) SP/min")
                            .font(.subheadline.bold().monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if currentSpeed < optimalSpeed {
                        Text("+\(optimalSpeed - currentSpeed) SP/min")
                            .font(.caption.bold())
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                }

                // Instruction
                VStack(alignment: .leading, spacing: 4) {
                    Label(remapReady ? "How to remap:" : "How to remap when ready:", systemImage: "info.circle")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("In EVE: Character Sheet → Neural Remap → Manually Remap. Set \(primary) to 27 and \(secondary) to 21. All others stay at 17. You have 14 free points (max 10 per attribute).")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Note: implant bonuses add on top of these base values and are not affected by the remap.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        )
    }

    // MARK: - Load

    private func load() async {
        isLoading = true
        error = nil
        var data: [CharacterRemapData] = []
        var lastError: Error?

        for account in accountManager.accounts {
            do {
                let token = try await accountManager.validToken(for: account)

                async let fetchAttrs: ESICharacterAttributes = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/attributes/", token: token
                )
                async let fetchQueue: [ESISkillQueue] = ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/skillqueue/", token: token
                )

                let (attrs, queue) = try await (fetchAttrs, fetchQueue)
                let activeQueue = queue.filter { ($0.finishDate ?? .distantPast) > Date() }

                // Batch-fetch type info for all queue skills
                let skillIDs = Array(Set(activeQueue.map(\.skillId)))
                let typeMap = await UniverseCache.shared.types(ids: skillIDs)

                // Calculate SP demand per attribute pair
                var pairSP: [String: Int] = [:]
                for entry in activeQueue {
                    let spNeeded = max((entry.levelEndSp ?? 0) - (entry.levelStartSp ?? 0), 0)
                    guard spNeeded > 0, let typeInfo = typeMap[entry.skillId],
                          let dogma = typeInfo.dogmaAttributes else { continue }

                    let primaryAttrID = dogma.first(where: { $0.attributeId == kPrimaryAttrID }).map { Int($0.value) }
                    let secondaryAttrID = dogma.first(where: { $0.attributeId == kSecondaryAttrID }).map { Int($0.value) }

                    if let pID = primaryAttrID, let sID = secondaryAttrID,
                       let pName = attrIDToKey[pID]?.capitalized,
                       let sName = attrIDToKey[sID]?.capitalized {
                        let key = "\(pName)/\(sName)"
                        pairSP[key, default: 0] += spNeeded
                    }
                }

                // Annual remap cooldown: 1 year after lastRemapDate (if no bonusRemaps)
                var nextAnnual: Date? = nil
                if let lastRemap = attrs.lastRemapDate {
                    let candidate = Calendar.current.date(byAdding: .year, value: 1, to: lastRemap)
                    if let candidate, candidate > Date() {
                        nextAnnual = candidate
                    }
                }

                data.append(CharacterRemapData(
                    characterID: account.characterID,
                    characterName: account.characterName,
                    attributes: attrs,
                    bonusRemaps: attrs.bonusRemaps ?? 0,
                    nextAnnualRemap: nextAnnual,
                    lastRemapDate: attrs.lastRemapDate,
                    queuePairs: pairSP
                ))
            } catch {
                lastError = error
            }
        }

        characterData = data
        if selectedCharacterID == nil { selectedCharacterID = data.first?.characterID }
        if data.isEmpty, let lastError { self.error = lastError.localizedDescription }
        isLoading = false
    }

    // MARK: - Helpers

    private func splitPair(_ key: String) -> (String, String) {
        let parts = key.components(separatedBy: "/")
        return (parts.first ?? key, parts.last ?? key)
    }

    private func pairColor(_ pair: String) -> Color {
        if pair.contains("Intelligence") { return .blue }
        if pair.contains("Perception") { return .green }
        if pair.contains("Willpower") { return .orange }
        if pair.contains("Charisma") { return .pink }
        return .cyan
    }

    private func attributeValue(_ attrs: ESICharacterAttributes, name: String) -> Int {
        switch name.lowercased() {
        case "intelligence": return attrs.intelligence
        case "memory":       return attrs.memory
        case "perception":   return attrs.perception
        case "willpower":    return attrs.willpower
        case "charisma":     return attrs.charisma
        default:             return 0
        }
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM SP", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK SP", Double(sp) / 1_000) }
        return "\(sp) SP"
    }

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Available" }
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        if days > 0 { return "\(days)d \(hours)h" }
        return "\(hours)h"
    }
}

// MARK: - Data Models

private struct CharacterRemapData {
    let characterID: Int
    let characterName: String
    let attributes: ESICharacterAttributes
    let bonusRemaps: Int
    let nextAnnualRemap: Date?
    let lastRemapDate: Date?
    let queuePairs: [String: Int]  // "Intelligence/Memory" → total SP needed
}

private extension Array {
    var second: Element? { count > 1 ? self[1] : nil }
}
