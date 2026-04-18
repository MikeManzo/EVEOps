import SwiftUI
import Charts

// Dogma attribute IDs for skill training attributes
private let kPrimaryAttrID = 180
private let kSecondaryAttrID = 181
private let attrIDToKey: [Int: String] = [
    164: "intelligence", 165: "charisma", 166: "memory",
    167: "perception", 168: "willpower"
]

// Dogma attribute IDs for attribute-enhancing implants (+1 through +5).
// Confirmed working: 175=cha, 176=mem, 177=per, 179=int.
// Willpower is unconfirmed — try both 178 (boost attr) and 168 (char attr ID) as candidates.
// Detection uses per-implant max to prevent double-counting if both IDs fire on the same type.
private let implantAttrIDs: [Int: String] = [
    168: "willpower",   // char attr ID fallback
    175: "charisma",
    176: "memory",
    177: "perception",
    178: "willpower",   // boost attr ID candidate
    179: "intelligence"
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
                        attributesSection(data)
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
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    Task {
                        await UniverseCache.shared.clearDiskCache()
                        await load()
                    }
                } label: {
                    Label("Refresh Implant Data", systemImage: "arrow.clockwise")
                }
                .help("Clears the local type cache and re-fetches implant data from ESI. Use this if implant bonuses appear incorrect.")
            }
        }
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
        HStack(spacing: 12) {
            // Bonus remaps pill
            Label("\(data.bonusRemaps) bonus remap\(data.bonusRemaps == 1 ? "" : "s")",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.bold())
                .foregroundStyle(data.bonusRemaps > 0 ? .green : .secondary)

            Divider().frame(height: 14)

            // Annual remap status
            if let cooldown = data.nextAnnualRemap, cooldown > now {
                Label("Annual: \(timeUntil(cooldown))", systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            } else {
                Label("Annual available", systemImage: "checkmark.circle")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }

            if let lastRemap = data.lastRemapDate {
                Divider().frame(height: 14)
                Label(EVEFormatters.dateFormatter.string(from: lastRemap), systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Attributes Section

    private func attributesSection(_ data: CharacterRemapData) -> some View {
        let attrs = data.attributes
        let bonuses = data.implantBonuses
        let attrList: [(String, Int, Int, Color)] = [
            ("Perception",   attrs.perception   - bonuses["perception",   default: 0], bonuses["perception",   default: 0], .green),
            ("Memory",       attrs.memory       - bonuses["memory",       default: 0], bonuses["memory",       default: 0], .cyan),
            ("Willpower",    attrs.willpower    - bonuses["willpower",    default: 0], bonuses["willpower",    default: 0], .orange),
            ("Intelligence", attrs.intelligence - bonuses["intelligence", default: 0], bonuses["intelligence", default: 0], .blue),
            ("Charisma",     attrs.charisma     - bonuses["charisma",     default: 0], bonuses["charisma",     default: 0], .pink),
        ]
        let maxVal = attrList.map { $0.1 + $0.2 }.max() ?? 1

        let pairs = data.queuePairs.sorted { $0.value > $1.value }
        let dominantPair = pairs.first.map { splitPair($0.key) }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Attributes")
                .font(.headline)

            HStack(alignment: .top, spacing: 24) {
                // Left: Current totals
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current")
                        .font(.subheadline.bold())
                    Text("Total values including implants.")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(attrList, id: \.0) { name, base, bonus, color in
                        let total = base + bonus
                        HStack(spacing: 10) {
                            Text(name)
                                .font(.subheadline)
                                .frame(width: 100, alignment: .trailing)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(color)
                                        .frame(width: geo.size.width * Double(total) / Double(maxVal + 5))
                                }
                            }
                            .frame(height: 16)
                            Text("\(total)")
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: Implant breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("Implants")
                        .font(.subheadline.bold())
                    Text("Base (light) plus attribute-enhancing implants (bright).")
                        .font(.caption).foregroundStyle(.secondary)

                    ForEach(attrList, id: \.0) { name, base, bonus, color in
                        HStack(spacing: 10) {
                            Text(name)
                                .font(.subheadline)
                                .frame(width: 100, alignment: .trailing)

                            Text(bonus > 0 ? "+\(bonus)" : "—")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(gradeColor(bonus).opacity(0.15))
                                .foregroundStyle(gradeColor(bonus))
                                .clipShape(Capsule())
                                .frame(width: 34)

                            GeometryReader { geo in
                                let scale = Double(maxVal + 5)
                                let baseW = geo.size.width * Double(base) / scale
                                let bonusW = geo.size.width * Double(bonus) / scale
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                    HStack(spacing: 0) {
                                        Rectangle().fill(color.opacity(0.35)).frame(width: baseW)
                                        if bonus > 0 {
                                            Rectangle().fill(color).frame(width: bonusW)
                                        }
                                    }
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                            .frame(height: 16)

                            Text("\(base + bonus)")
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(width: 32, alignment: .trailing)
                        }
                    }

                    if let (primary, secondary) = dominantPair {
                        let primaryBonus = bonuses[primary.lowercased(), default: 0]
                        let secondaryBonus = bonuses[secondary.lowercased(), default: 0]
                        let upgradeGain = (5 - primaryBonus) + (5 - secondaryBonus) / 2
                        if upgradeGain > 0 {
                            Divider()
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Implant Upgrade Potential")
                                        .font(.caption.bold())
                                    let pLabel = primaryBonus > 0 ? "+\(primaryBonus) → +5" : "none → +5"
                                    let sLabel = secondaryBonus > 0 ? "+\(secondaryBonus) → +5" : "none → +5"
                                    Text("\(primary) (\(pLabel)) and \(secondary) (\(sLabel)): up to +\(upgradeGain) SP/min.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func gradeColor(_ bonus: Int) -> Color {
        switch bonus {
        case 0:    return .secondary
        case 1, 2: return .blue
        case 3:    return .teal
        case 4:    return .orange
        default:   return .green
        }
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

                if let dominant = pairs.first {
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

    /// EVE remap pool: 5 attributes × base 17 + 14 free remap points = 99 base total (implants add on top).
    /// Optimal for one pair: put 10 into primary (base → 27), 4 into secondary (base → 21), rest stay at base 17.
    private func recommendationCard(_ data: CharacterRemapData) -> some View {
        let pairs = data.queuePairs.sorted { $0.value > $1.value }
        guard let dominant = pairs.first else { return AnyView(EmptyView()) }

        let totalSP = pairs.reduce(0) { $0 + $1.value }
        let dominantPct = Int(Double(dominant.value) / Double(max(totalSP, 1)) * 100)
        let (primary, secondary) = splitPair(dominant.key)

        // Recommended base values after optimal remap for this pair (base only, before implants)
        let recommended: [(String, Int, Color)] = [
            ("Perception",   primary == "Perception"   ? 27 : secondary == "Perception"   ? 21 : 17, .green),
            ("Memory",       primary == "Memory"       ? 27 : secondary == "Memory"       ? 21 : 17, .cyan),
            ("Willpower",    primary == "Willpower"    ? 27 : secondary == "Willpower"    ? 21 : 17, .orange),
            ("Intelligence", primary == "Intelligence" ? 27 : secondary == "Intelligence" ? 21 : 17, .blue),
            ("Charisma",     primary == "Charisma"     ? 27 : secondary == "Charisma"     ? 21 : 17, .pink),
        ]

        let remapReady = data.bonusRemaps > 0
            || data.nextAnnualRemap == nil
            || (data.nextAnnualRemap.map { $0 <= now } ?? false)

        // Current speed for the dominant pair (includes implant bonuses in current attrs)
        let curPrimary = attributeValue(data.attributes, name: primary)
        let curSecondary = attributeValue(data.attributes, name: secondary)
        let currentSpeed = curPrimary + curSecondary / 2

        // Optimal speed after remap, preserving current implants (base 27/21 + implants)
        let implantP = data.implantBonuses[primary.lowercased(), default: 0]
        let implantS = data.implantBonuses[secondary.lowercased(), default: 0]
        let optimalSpeed = (27 + implantP) + (21 + implantS) / 2

        // Theoretical max with +5 implants on both
        let maxSpeed = (27 + 5) + (21 + 5) / 2  // = 45

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

                // Single table: target values to enter in EVE's remap screen (floor + allocated points)
                // floor = 17 + implant; allocation = 10 (primary), 4 (secondary), 0 (others)
                let remapAttrs: [(String, Int, Int, Int, Color)] = recommended.map { name, base, color in
                    let implant = data.implantBonuses[name.lowercased(), default: 0]
                    let floor   = 17 + implant          // minimum shown in EVE's remap screen
                    let alloc   = base - 17             // remap points added (0, 4, or 10)
                    return (name, floor, alloc, floor + alloc, color)
                }
                let remapMax = remapAttrs.map { $0.1 + $0.2 }.max() ?? 1

                VStack(alignment: .leading, spacing: 4) {
                    Text("Enter in EVE's Remap Screen")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text("Floor (muted) = 17 + implants. Bright segment = remap points added.")
                        .font(.caption2).foregroundStyle(.tertiary)

                    VStack(spacing: 6) {
                        ForEach(remapAttrs, id: \.0) { name, floor, alloc, total, color in
                            let isPrimary   = name == primary
                            let isSecondary = name == secondary
                            HStack(spacing: 8) {
                                Text(name)
                                    .font(.subheadline)
                                    .frame(width: 110, alignment: .trailing)
                                GeometryReader { geo in
                                    let scale  = Double(remapMax + 3)
                                    let floorW = geo.size.width * Double(floor) / scale
                                    let allocW = geo.size.width * Double(alloc) / scale
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4).fill(.quaternary)
                                        HStack(spacing: 0) {
                                            Rectangle()
                                                .fill(isPrimary || isSecondary ? color.opacity(0.3) : Color.secondary.opacity(0.2))
                                                .frame(width: floorW)
                                            if alloc > 0 {
                                                Rectangle()
                                                    .fill(isPrimary ? color : color.opacity(0.65))
                                                    .frame(width: allocW)
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                .frame(height: 16)
                                Text("\(total)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .frame(width: 32, alignment: .trailing)
                                    .foregroundStyle(isPrimary ? color : isSecondary ? color.opacity(0.75) : .secondary)
                                Text(isPrimary ? "Primary (+10)" : isSecondary ? "Secondary (+4)" : "Floor (+0)")
                                    .font(.caption2)
                                    .foregroundStyle(isPrimary ? color.opacity(0.8) : isSecondary ? color.opacity(0.6) : Color.secondary.opacity(0.5))
                                    .frame(width: 100, alignment: .leading)
                            }
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
                        Text("After remap")
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
                    if optimalSpeed < maxSpeed {
                        VStack(spacing: 2) {
                            Text("+5 implants")
                                .font(.caption).foregroundStyle(.secondary)
                            Text("\(maxSpeed) SP/min")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Instruction
                VStack(alignment: .leading, spacing: 4) {
                    Label(remapReady ? "How to remap:" : "How to remap when ready:", systemImage: "info.circle")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Text("In EVE: Character Sheet → Neural Remap → Manually Remap. Set each attribute to the value shown in the table above. EVE's remap screen shows the floor automatically — just drag each slider to the target number. This uses all 14 remap points (10 to \(primary), 4 to \(secondary)).")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Note: if an implant is not detected, its floor may show slightly low. The allocations (+10 / +4 / +0) are always correct regardless.")
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

                // Fetch active implants and resolve their attribute bonuses
                let implantIDs: [Int] = (try? await ESIClient.shared.fetch(
                    "/characters/\(account.characterID)/implants/", token: token
                )) ?? []
                let implantTypeMap = await UniverseCache.shared.types(ids: implantIDs)
                var implantBonuses: [String: Int] = [:]
                for typeInfo in implantTypeMap.values {
                    guard let dogma = typeInfo.dogmaAttributes else { continue }
                    // Collect per-type max per attribute name to avoid double-counting
                    // when multiple candidate IDs match the same attribute on the same implant.
                    var typeBonus: [String: Int] = [:]
                    for attr in dogma {
                        if let attrName = implantAttrIDs[attr.attributeId] {
                            let v = Int(attr.value)
                            typeBonus[attrName] = max(typeBonus[attrName, default: 0], v)
                        }
                    }
                    for (name, bonus) in typeBonus {
                        implantBonuses[name, default: 0] += bonus
                    }
                }

                // Batch-fetch type info for all queue skills
                let skillIDs = Array(Set(activeQueue.map(\.skillId)))
                let typeMap = await UniverseCache.shared.types(ids: skillIDs)

                // Calculate SP demand per attribute pair
                var pairSP: [String: Int] = [:]
                for entry in activeQueue {
                    // Use trainingStartSp (actual progress) for the in-progress skill;
                    // fall back to levelStartSp (full level cost) for queued-but-not-started skills.
                    let startSP = entry.trainingStartSp ?? entry.levelStartSp ?? 0
                    let spNeeded = max((entry.levelEndSp ?? 0) - startSP, 0)
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
                    queuePairs: pairSP,
                    implantBonuses: implantBonuses
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
    let queuePairs: [String: Int]       // "Intelligence/Memory" → total SP needed
    let implantBonuses: [String: Int]   // "intelligence" → implant bonus (0 if none)
}

private extension Array {
    var second: Element? { count > 1 ? self[1] : nil }
}
