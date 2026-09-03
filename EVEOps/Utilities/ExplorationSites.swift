//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation

// MARK:  Exploration Site Codex — curated reference data
//
// ESI exposes no live scanning / probe data, so this screen is a planning aid:
// a curated catalogue of Ghost Sites (Covert Research Facilities) and Sleeper
// Caches, cross-referenced at runtime with live Jita prices, the signed-in
// character's skills / implants, and a response-fleet timer.
//
// Timers, blast-damage figures and loot tables are community-sourced and change
// with balance passes — every screen that shows them also shows a "verify
// in-game" disclaimer. Loot is stored by name and resolved to type IDs through
// `/universe/ids/` so a renamed item degrades to "unpriced" rather than showing
// stale data.

enum ExplorationSiteKind: String, CaseIterable, Identifiable, Sendable {
    case ghostSite = "Ghost Sites"
    case sleeperCache = "Sleeper Caches"
    var id: String { rawValue }

    var blurb: String {
        switch self {
        case .ghostSite:
            return "Covert Research Facilities. A short timer runs from the moment you land — hack the good cans and leave before the response fleet arrives and the containers self-destruct. A failed hack detonates the can for omni damage that scales with how dangerous the space is."
        case .sleeperCache:
            return "Unrated deadspace pockets in known space and wormholes. No rats on landing, but damage clouds, automated Sleeper defenses and collapsing structures punish a sloppy approach. High-strength hacking and a strong omni tank are the price of entry; Superior caches pay it back many times over."
        }
    }
}

enum HazardSeverity: Int, Sendable, Comparable {
    case info, caution, severe, lethal
    static func < (a: HazardSeverity, b: HazardSeverity) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .info: return "Note"
        case .caution: return "Caution"
        case .severe: return "Severe"
        case .lethal: return "Lethal"
        }
    }
}

struct SiteHazard: Identifiable, Sendable {
    let name: String
    let detail: String
    let severity: HazardSeverity
    var id: String { name }
}

enum HackingDifficulty: Int, Sendable {
    case low, moderate, high, extreme

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .extreme: return "Extreme"
        }
    }

    /// Core hacking-skill level (Hacking for data, Archaeology for relic) advised
    /// before attempting the site with a Tier-2 analyzer.
    var recommendedCoreLevel: Int {
        switch self {
        case .low: return 3
        case .moderate: return 4
        case .high, .extreme: return 5
        }
    }

    /// True when a virus-strength / coherence implant is effectively required for
    /// a reliable success rate.
    var wantsImplant: Bool { self == .extreme }

    var blurb: String {
        switch self {
        case .low:
            return "A Tier-1 analyzer clears these with a little care."
        case .moderate:
            return "A Tier-2 analyzer and the core skill at IV keeps the failure rate low."
        case .high:
            return "Tier-2 analyzer, core skill at V. Expect a rescue node or two."
        case .extreme:
            return "Tier-2 analyzer, core skill at V, and a coherence/strength implant. Some nodes are near the ceiling of what is possible."
        }
    }
}

struct SiteLootEntry: Identifiable, Sendable {
    /// Exact in-game name — resolved to a type ID via `/universe/ids/`.
    let name: String
    /// Short note on where it drops / what it feeds.
    let note: String
    /// The headline drop that makes the site worth running.
    let isJackpot: Bool
    var id: String { name }

    init(_ name: String, _ note: String, jackpot: Bool = false) {
        self.name = name
        self.note = note
        self.isJackpot = jackpot
    }
}

struct ExplorationSite: Identifiable, Sendable {
    let id: String
    let kind: ExplorationSiteKind
    let name: String
    /// 1-based ordering within a kind (easiest → hardest).
    let tier: Int
    let space: String
    let rats: String
    let summary: String
    let mechanics: [String]
    let hazards: [SiteHazard]
    let hackingDifficulty: HackingDifficulty
    /// Approximate omni explosion damage from a failed hack (Ghost Sites only).
    let blastDamage: Int?
    /// Seconds between landing and the response fleet arriving (Ghost Sites only).
    let responseWindow: ClosedRange<Int>?
    let loot: [SiteLootEntry]
    let tactics: [String]
    let recommendedShips: String

    var isGhostSite: Bool { kind == .ghostSite }
}

// MARK:  Catalogue

enum ExplorationCatalog {
    static let sites: [ExplorationSite] = ghostSites + sleeperCaches

    static func sites(for kind: ExplorationSiteKind) -> [ExplorationSite] {
        sites.filter { $0.kind == kind }.sorted { $0.tier < $1.tier }
    }

    /// Every distinct loot name in the catalogue — resolved in one batch call.
    static var allLootNames: [String] {
        Array(Set(sites.flatMap { $0.loot.map(\.name) })).sorted()
    }

    // MARK: Ghost Sites

    private static let ghostRats =
        "Pirate faction response fleet (Serpentis / Guristas / Sansha / Blood Raider / Angel) — frigates and cruisers with warp disruption and energy neutralizers."

    private static let ghostSites: [ExplorationSite] = [
        ExplorationSite(
            id: "ghost-lesser",
            kind: .ghostSite,
            name: "Lesser Covert Research Facility",
            tier: 1,
            space: "High-sec (0.5 – 1.0)",
            rats: ghostRats,
            summary: "The training-wheels Ghost Site. The response fleet is light and the can explosions rarely threaten a fit exploration frigate, but the timer is just as unforgiving as the higher tiers.",
            mechanics: [
                "Three to four Covert Research data containers, only some of which hold the good loot.",
                "A hidden timer starts the moment the first can is hacked (or shortly after landing).",
                "When it expires the response fleet warps in and the remaining containers self-destruct — the site then despawns.",
                "A failed hack detonates that container immediately."
            ],
            hazards: [
                SiteHazard(name: "Can detonation", detail: "≈ 1,000 omni damage on a failed hack. A shield-tanked cov ops with any buffer survives one; back-to-back failures do not.", severity: .caution),
                SiteHazard(name: "Response fleet", detail: "Arrives on the timer with points and neuts. Treat its appearance as 'leave now'.", severity: .severe),
                SiteHazard(name: "Timer", detail: "You will not clear every can. Scan them, hack the valuable ones, accept leaving loot behind.", severity: .info)
            ],
            hackingDifficulty: .low,
            blastDamage: 1_000,
            responseWindow: 90...150,
            loot: [
                SiteLootEntry("Covert Research Tools", "Bulk consumable — the reliable ISK floor of every Ghost Site."),
                SiteLootEntry("Parity Decryptor", "Invention decryptor."),
                SiteLootEntry("Process Decryptor", "Invention decryptor."),
                SiteLootEntry("Datacore - Electromagnetic Physics", "Invention datacore."),
                SiteLootEntry("Caldari Navy Antimatter Charge M Blueprint", "Faction ammo BPC — the jackpot roll; faction and size vary, and faction module BPCs also appear here.", jackpot: true)
            ],
            tactics: [
                "Fit a Cargo Scanner: check each can before you burn to it and skip the junk.",
                "Pre-align to a safe or a station before the first hack.",
                "Bring nanite paste / a second analyzer — a failed hack is a wasted can, not a wasted trip.",
                "If the response fleet lands, warp. The remaining loot is not worth the ship."
            ],
            recommendedShips: "Any Tech-1 exploration frigate (Heron / Imicus / Magnate / Probe) or a covert ops."
        ),
        ExplorationSite(
            id: "ghost-standard",
            kind: .ghostSite,
            name: "Standard Covert Research Facility",
            tier: 2,
            space: "Low-sec (0.1 – 0.4)",
            rats: ghostRats,
            summary: "The low-sec tier. The loot table steps up, and so does the explosion — a bare-hull frigate can die to a single failed hack here.",
            mechanics: [
                "Same structure as the Lesser site: several data cans, a timer, a self-destruct.",
                "Response fleet is heavier — expect cruisers alongside the frigates.",
                "The explosion radius is generous; keep only one ship near a can at a time in a fleet."
            ],
            hazards: [
                SiteHazard(name: "Can detonation", detail: "≈ 2,200 omni damage. A shield exploration frigate needs a real buffer (Extender + rigs) to eat one comfortably.", severity: .severe),
                SiteHazard(name: "Response fleet", detail: "Cruiser-weight, with points and neuts. No warning beyond the timer.", severity: .severe),
                SiteHazard(name: "Local", detail: "Low-sec — the site is visible to everyone who scans, and you are the softest target in system.", severity: .caution)
            ],
            hackingDifficulty: .moderate,
            blastDamage: 2_200,
            responseWindow: 75...135,
            loot: [
                SiteLootEntry("Covert Research Tools", "Reliable bulk ISK."),
                SiteLootEntry("Accelerant Decryptor", "Invention decryptor."),
                SiteLootEntry("Attainment Decryptor", "Invention decryptor."),
                SiteLootEntry("Datacore - Rocket Science", "Invention datacore."),
                SiteLootEntry("Republic Fleet EMP M Blueprint", "Faction ammo BPC — jackpot; faction/size vary, and faction module BPCs also roll here.", jackpot: true)
            ],
            tactics: [
                "Cargo Scanner is now mandatory — you have time for maybe two cans.",
                "Fit for a fast align and pre-align out.",
                "Watch d-scan constantly; a combat probe hit means leave.",
                "Buffer over rep — you need to survive one blast, not tank a fight."
            ],
            recommendedShips: "Buffer-fit covert ops, or an Astero for the extra tank and cloak."
        ),
        ExplorationSite(
            id: "ghost-improved",
            kind: .ghostSite,
            name: "Improved Covert Research Facility",
            tier: 3,
            space: "Null-sec (0.0)",
            rats: ghostRats,
            summary: "Null-sec tier. The explosion is now lethal to anything frigate-sized without a serious buffer, and the response fleet will hold you long enough to die.",
            mechanics: [
                "Cans, timer, self-destruct — unchanged.",
                "Response fleet is battlecruiser-weight and lands with hard points.",
                "Sites tend to spawn in ratting constellations, so intel and hostiles arrive quickly."
            ],
            hazards: [
                SiteHazard(name: "Can detonation", detail: "≈ 5,200 omni damage. Realistically a one-blast-and-out proposition even for a well-buffered ship.", severity: .lethal),
                SiteHazard(name: "Response fleet", detail: "Points, neuts, and enough DPS to kill a frigate before it aligns. Do not trade with it.", severity: .lethal),
                SiteHazard(name: "Locals", detail: "Someone owns this space. Watch intel channels and the map for spikes.", severity: .severe)
            ],
            hackingDifficulty: .high,
            blastDamage: 5_200,
            responseWindow: 70...120,
            loot: [
                SiteLootEntry("Covert Research Tools", "Bulk ISK."),
                SiteLootEntry("Augmentation Decryptor", "Invention decryptor."),
                SiteLootEntry("Optimized Attainment Decryptor", "High-value invention decryptor."),
                SiteLootEntry("Datacore - Nanite Engineering", "Invention datacore."),
                SiteLootEntry("Imperial Navy Multifrequency L Blueprint", "Faction ammo BPC — jackpot; faction/size vary, and faction module BPCs also roll here.", jackpot: true)
            ],
            tactics: [
                "One hack, maybe two. Scan first, take the best can, warp.",
                "Never sit still — orbit the can at speed while the virus runs.",
                "Have a bookmarked safe or a wormhole exit picked before you land.",
                "If you are not confident of the align time, do not open a can."
            ],
            recommendedShips: "Covert ops with a full buffer, or a Stratios / T3 for the tank if you accept the align penalty."
        ),
        ExplorationSite(
            id: "ghost-superior",
            kind: .ghostSite,
            name: "Superior Covert Research Facility",
            tier: 4,
            space: "Wormhole space (all classes)",
            rats: ghostRats,
            summary: "The wormhole tier and the richest. Everything is turned to maximum: the explosion, the response fleet, and the near-total lack of intel about who else is in the hole with you.",
            mechanics: [
                "Cans, timer, self-destruct — the same loop, least forgiving execution.",
                "Response fleet is the heaviest of the four tiers.",
                "No local. Assume you are not alone and that a cloaked hunter has already seen you."
            ],
            hazards: [
                SiteHazard(name: "Can detonation", detail: "≈ 7,600 omni damage. Only a genuinely buffer-fit cruiser-plus survives one, and rarely two.", severity: .lethal),
                SiteHazard(name: "Response fleet", detail: "Heavy, fast to point. It exists to make sure a greedy pilot does not get a second hack.", severity: .lethal),
                SiteHazard(name: "No local", detail: "You get no warning of hostiles. Roll or watch your entry hole and keep d-scan spinning.", severity: .lethal)
            ],
            hackingDifficulty: .extreme,
            blastDamage: 7_600,
            responseWindow: 60...110,
            loot: [
                SiteLootEntry("Covert Research Tools", "Bulk ISK — even the floor is high here."),
                SiteLootEntry("Optimized Augmentation Decryptor", "Top-tier invention decryptor."),
                SiteLootEntry("Symmetry Decryptor", "Invention decryptor."),
                SiteLootEntry("Datacore - Quantum Physics", "Invention datacore."),
                SiteLootEntry("Guristas Scourge Heavy Missile Blueprint", "Faction ammo BPC — jackpot; faction/size vary, and faction module BPCs also roll here.", jackpot: true)
            ],
            tactics: [
                "Roll your static or bookmark your exit before you touch a can.",
                "Cargo Scanner + one hack. This is not a site you clear — it is a site you raid.",
                "Cloak up between actions if your hull can.",
                "Assume the response fleet timer is the short end of the range."
            ],
            recommendedShips: "Buffer-fit Stratios, or a defensive T3 cruiser. Speed and align beat tank if you only take one can."
        )
    ]

    // MARK: Sleeper Caches

    private static let sleeperDefenses =
        "No rats on landing. Automated Sleeper sentry turrets and — from the Standard tier up — 'Emergent' defensive batteries that activate on proximity or on a failed hack, applying webs, neuts and heavy omni damage."

    private static let sleeperCaches: [ExplorationSite] = [
        ExplorationSite(
            id: "cache-limited",
            kind: .sleeperCache,
            name: "Limited Sleeper Cache",
            tier: 1,
            space: "Known space (all security) and wormholes",
            rats: sleeperDefenses,
            summary: "The entry-level cache. One main pocket, a handful of hackable structures, and damage clouds you can mostly fly around. A well-tanked cruiser with a decent analyzer clears it solo.",
            mechanics: [
                "Hack the 'Intact/Malfunctioning/Wrecked Artificial Neural Network' containers for the payout.",
                "Coloured clouds apply continuous damage or utility effects — read each cloud before you enter it.",
                "Destroying or hacking certain structures starts a short countdown to an area detonation.",
                "The site does not despawn on a timer, but the defenses escalate the longer you stay."
            ],
            hazards: [
                SiteHazard(name: "Damage clouds", detail: "Continuous omni damage while inside. Survivable for a tanked cruiser in short bursts; do not park in one.", severity: .caution),
                SiteHazard(name: "Sleeper turrets", detail: "Static defenses that wake on proximity. Predictable, but they add up with the clouds.", severity: .caution),
                SiteHazard(name: "Structure collapse", detail: "Timed AoE after you interfere with a structure — burn clear when the warning fires.", severity: .severe)
            ],
            hackingDifficulty: .moderate,
            blastDamage: nil,
            responseWindow: nil,
            loot: [
                SiteLootEntry("Trinary Data", "Feeds Upwell structure and Tech-2 component production — the staple drop."),
                SiteLootEntry("Wrecked Artificial Neural Network", "Salvage-tier component."),
                SiteLootEntry("Malfunctioning Artificial Neural Network", "Mid-tier component."),
                SiteLootEntry("Neural Network Analyzer", "Higher-value component; not every run.", jackpot: true)
            ],
            tactics: [
                "Fit an omni tank — Sleeper damage is spread across all four types with an EM/Thermal lean.",
                "MWD to cross open gaps, then cut it before entering a cloud to keep your signature down.",
                "Hack from outside a cloud whenever the range allows.",
                "Learn the collapse warning and move on it every time."
            ],
            recommendedShips: "Well-tanked Tech-1 exploration cruiser (Stratios excels), or a shield cruiser with an omni buffer."
        ),
        ExplorationSite(
            id: "cache-standard",
            kind: .sleeperCache,
            name: "Standard Sleeper Cache",
            tier: 2,
            space: "Known space (all security) and wormholes",
            rats: sleeperDefenses,
            summary: "The mid tier. Multiple pockets, denser clouds, and 'Emergent' batteries that punish a failed hack. Runnable solo in a strong hull, better with a fleet.",
            mechanics: [
                "Several sub-pockets gated by hackable acceleration structures.",
                "Emergent defensive batteries activate on a failed hack or when you get close — they neut and web.",
                "Utility clouds exist alongside the damage clouds; some repair, some boost — use them deliberately.",
                "Structure collapses here hit harder and cover more area."
            ],
            hazards: [
                SiteHazard(name: "Emergent batteries", detail: "Wake on a failed hack. Neuts + webs + heavy omni DPS — a failed hack can start a fight you did not plan for.", severity: .severe),
                SiteHazard(name: "Damage clouds", detail: "Denser and larger than the Limited cache. Sustained exposure will break a mediocre tank.", severity: .severe),
                SiteHazard(name: "Structure collapse", detail: "Wide-area AoE with a short fuse. Position so you always have an exit vector.", severity: .severe)
            ],
            hackingDifficulty: .high,
            blastDamage: nil,
            responseWindow: nil,
            loot: [
                SiteLootEntry("Trinary Data", "Bulk industrial staple."),
                SiteLootEntry("Neurolink Protection Cell", "High-value component for capital / Upwell production.", jackpot: true),
                SiteLootEntry("Neural Network Analyzer", "High-value component."),
                SiteLootEntry("Malfunctioning Artificial Neural Network", "Mid-tier component."),
                SiteLootEntry("Intact Artificial Neural Network", "Top salvage-tier component.", jackpot: true)
            ],
            tactics: [
                "Tier-2 analyzer, core skill at V — a failed hack here is expensive.",
                "Bring a second analyzer and nanite paste.",
                "Keep transversal on the batteries once they are awake; do not sit still to hack under fire.",
                "If solo, clear one pocket and leave with the loot rather than pushing the whole site."
            ],
            recommendedShips: "Defensive Tech-3 cruiser, a well-fit Stratios, or a small fleet of cruisers with a dedicated hacker."
        ),
        ExplorationSite(
            id: "cache-superior",
            kind: .sleeperCache,
            name: "Superior Sleeper Cache",
            tier: 3,
            space: "Known space (all security) and wormholes",
            rats: sleeperDefenses,
            summary: "The top tier and one of the richest PvE sites in the game — a full clear runs into the hundreds of millions and up. Every hazard is at maximum and the hacking is near the ceiling of what is possible.",
            mechanics: [
                "Multiple deep pockets, each gated behind an extreme-difficulty hack.",
                "The densest clouds in the site family, including layered damage + web zones.",
                "Emergent defenses are numerous and hit like a rat battleship.",
                "Structure collapses can chain — clearing one can trigger the next."
            ],
            hazards: [
                SiteHazard(name: "Extreme hacking", detail: "Near the top of the difficulty range. Without core skill V and a coherence/strength implant, expect to fail nodes and wake the site.", severity: .lethal),
                SiteHazard(name: "Layered clouds", detail: "Damage and speed-reduction clouds overlap. Getting webbed inside a damage cloud is how ships die here.", severity: .lethal),
                SiteHazard(name: "Emergent defenses", detail: "Battleship-weight automated DPS with neuts. A soft tank does not leave.", severity: .lethal),
                SiteHazard(name: "Chained collapse", detail: "AoE detonations can cascade. Never be between two live structures.", severity: .severe)
            ],
            hackingDifficulty: .extreme,
            blastDamage: nil,
            responseWindow: nil,
            loot: [
                SiteLootEntry("Trinary Data", "Bulk staple — large stacks here."),
                SiteLootEntry("Neurolink Protection Cell", "Major payout; capital / Upwell production input.", jackpot: true),
                SiteLootEntry("Antikythera Element", "Signature Superior-cache drop; capital-scale industrial demand.", jackpot: true),
                SiteLootEntry("Neural Network Analyzer", "High-value component."),
                SiteLootEntry("Intact Artificial Neural Network", "Top salvage-tier component.", jackpot: true)
            ],
            tactics: [
                "Do not attempt without Hacking / Archaeology V and a virus implant — a woken Superior cache kills unprepared hulls.",
                "Fly a bastion / defensive T3 or a Marauder-tier tank; you may have to ride out clouds and defenses while a hack runs.",
                "Map the collapse structures before you touch any of them.",
                "Two people — one tank, one hacker — turns a lethal site into a routine one."
            ],
            recommendedShips: "Defensive Tech-3 cruiser with a heavy buffer, a Marauder in bastion, or a two-pilot cruiser team."
        )
    ]
}

// MARK:  Readiness

/// Which core skills / implants a character has that matter for exploration hacking.
struct ExplorationSkillProfile: Sendable, Equatable {
    var hacking = 0
    var archaeology = 0
    var astrometrics = 0
    /// Names of the character's active implants that boost virus coherence / strength.
    var relevantImplants: [String] = []
    /// True once a real skills payload has been applied (vs. the signed-out default).
    var loaded = false

    var hasVirusImplant: Bool { !relevantImplants.isEmpty }

    /// Substrings that identify a virus-coherence / strength implant by name, so we
    /// never depend on brittle hard-coded type IDs.
    static let implantNameMarkers = ["'Prospector'", "AC-905", "HC-905", "Zeugma"]

    static func classifyImplant(name: String) -> Bool {
        implantNameMarkers.contains { name.localizedCaseInsensitiveContains($0) }
    }
}

enum ReadinessVerdict: Sendable {
    case ready, marginal, underSkilled, unknown

    var label: String {
        switch self {
        case .ready: return "Ready"
        case .marginal: return "Marginal"
        case .underSkilled: return "Under-skilled"
        case .unknown: return "Sign in to check"
        }
    }
}

struct SiteReadiness: Sendable {
    let verdict: ReadinessVerdict
    /// The core skill this site keys off, and the character's level in it.
    let coreSkillName: String
    let coreSkillLevel: Int
    let recommendedLevel: Int
    let wantsImplant: Bool
    let hasImplant: Bool
    let notes: [String]

    static func evaluate(site: ExplorationSite, profile: ExplorationSkillProfile) -> SiteReadiness {
        guard profile.loaded else {
            return SiteReadiness(
                verdict: .unknown,
                coreSkillName: site.isGhostSite ? "Hacking" : "Hacking / Archaeology",
                coreSkillLevel: 0,
                recommendedLevel: site.hackingDifficulty.recommendedCoreLevel,
                wantsImplant: site.hackingDifficulty.wantsImplant,
                hasImplant: false,
                notes: ["Sign in with a character to check skills and implants against this site."]
            )
        }

        let want = site.hackingDifficulty.recommendedCoreLevel
        let wantsImplant = site.hackingDifficulty.wantsImplant
        let hasImplant = profile.hasVirusImplant

        // Ghost Sites are pure data hacks. Sleeper Caches mix data and relic cans,
        // so the limiting factor is the weaker of the two core skills.
        let coreName: String
        let coreLevel: Int
        if site.isGhostSite {
            coreName = "Hacking"
            coreLevel = profile.hacking
        } else {
            coreName = "Hacking / Archaeology"
            coreLevel = min(profile.hacking, profile.archaeology)
        }

        var notes: [String] = []
        var verdict: ReadinessVerdict

        if coreLevel >= want && (!wantsImplant || hasImplant) {
            verdict = .ready
        } else if coreLevel >= want - 1 {
            verdict = .marginal
        } else {
            verdict = .underSkilled
        }

        if coreLevel < want {
            notes.append("Train \(coreName) to \(romanNumeral(want)) (currently \(romanNumeral(coreLevel))).")
        }
        if !site.isGhostSite && profile.hacking != profile.archaeology {
            notes.append("Sleeper caches have both data and relic cans — level whichever of Hacking / Archaeology is lower.")
        }
        if wantsImplant && !hasImplant {
            notes.append("Fit a virus-coherence implant (Poteque 'Prospector' AC-905 / HC-905, or a Zeugma set) for a reliable success rate.")
        } else if wantsImplant && hasImplant {
            notes.append("Virus implant detected: \(profile.relevantImplants.joined(separator: ", ")).")
        }
        if profile.astrometrics < 3 {
            notes.append("Astrometrics \(romanNumeral(profile.astrometrics)) — train it toward IV/V to scan these signatures down faster.")
        }
        if verdict == .ready && notes.isEmpty {
            notes.append("Skills and implants clear this site's hacking requirement.")
        }

        return SiteReadiness(
            verdict: verdict,
            coreSkillName: coreName,
            coreSkillLevel: coreLevel,
            recommendedLevel: want,
            wantsImplant: wantsImplant,
            hasImplant: hasImplant,
            notes: notes
        )
    }
}

// MARK:  Blast survivability (Ghost Sites)

enum BlastSurvivability: Sendable {
    case safe, risky, lethal, unknown

    var label: String {
        switch self {
        case .safe: return "Survivable"
        case .risky: return "Risky"
        case .lethal: return "Lethal"
        case .unknown: return "Enter your EHP"
        }
    }

    /// `ehp` is the ship's worst-case (minimum-resist) effective HP.
    static func evaluate(ehp: Double?, blast: Int?) -> BlastSurvivability {
        guard let blast, blast > 0 else { return .unknown }
        guard let ehp, ehp > 0 else { return .unknown }
        let ratio = ehp / Double(blast)
        if ratio >= 2.0 { return .safe }
        if ratio >= 1.0 { return .risky }
        return .lethal
    }
}

// MARK:  Market signal (Tier 2 #4)
//
// Derived from a `MarketHistoryService.Series` in the view layer and handed to
// the signal UI as a plain value type. "Current" is the most recent daily
// average; the delta is measured against the 30-day median, matching the
// "vs 30-day median" idiom used elsewhere in the app. The verdict is framed
// from the runner's point of view — you loot the site and sell the drops, so a
// price above its norm is a good thing.

enum PriceSignal: Sendable {
    case spiking, elevated, normal, soft, unknown

    var label: String {
        switch self {
        case .spiking: return "Spiking"
        case .elevated: return "Elevated"
        case .normal: return "In line"
        case .soft: return "Soft"
        case .unknown: return "No data"
        }
    }

    /// Short, runner-facing interpretation.
    var advice: String {
        switch self {
        case .spiking: return "well above its 30-day norm — good time to sell drops"
        case .elevated: return "above its 30-day norm"
        case .normal: return "tracking its 30-day norm"
        case .soft: return "below its 30-day norm — consider banking drops for now"
        case .unknown: return "no recent Jita history"
        }
    }

    static func from(deltaPct: Double?) -> PriceSignal {
        guard let d = deltaPct else { return .unknown }
        switch d {
        case 25...: return .spiking
        case 8..<25: return .elevated
        case -8..<8: return .normal
        default: return .soft
        }
    }
}

struct LootMarketStat: Identifiable, Sendable {
    let name: String
    let typeID: Int?
    let isJackpot: Bool
    /// Most recent daily-average price on the Jita market.
    let current: Double?
    /// Median daily-average price over the last 30 days of history.
    let median30: Double?
    var id: String { name }

    /// Current price vs the 30-day median, as a percentage.
    var deltaPct: Double? {
        guard let current, let median30, median30 > 0 else { return nil }
        return (current - median30) / median30 * 100
    }

    var signal: PriceSignal { PriceSignal.from(deltaPct: deltaPct) }
}

/// Aggregate market read for a whole site's loot table.
struct SiteMarketSignal: Sendable {
    let stats: [LootMarketStat]

    /// Sum of current unit prices for the non-jackpot consumables we could price.
    var consumableFloor: Double {
        stats.filter { !$0.isJackpot }.compactMap(\.current).reduce(0, +)
    }

    /// Mean delta across every priced item — the site-wide "are drops hot right
    /// now" number.
    var aggregateDeltaPct: Double? {
        let deltas = stats.compactMap(\.deltaPct)
        guard !deltas.isEmpty else { return nil }
        return deltas.reduce(0, +) / Double(deltas.count)
    }

    var aggregateSignal: PriceSignal { PriceSignal.from(deltaPct: aggregateDeltaPct) }

    /// typeID of the highest-signal jackpot item, for a detail chart.
    var featuredJackpotTypeID: Int? {
        stats.first(where: { $0.isJackpot && $0.typeID != nil })?.typeID
            ?? stats.first(where: { $0.typeID != nil })?.typeID
    }
}

// MARK:  Run ledger (Tier 2 #6)
//
// A private, on-device log of completed site runs. Exploration-loot sales are
// not tagged in the wallet journal, so there is nothing to correlate against —
// the runner records the haul value (valued at Jita average from the loot
// table) and an optional duration, and the ledger turns that into per-site
// ISK / run and ISK / hour history.

struct ExplorationRun: Codable, Identifiable, Sendable {
    var id = UUID()
    let siteID: String
    let date: Date
    let iskValue: Double
    /// Wall-clock minutes for the run, if the pilot entered one.
    let minutes: Int?

    var iskPerHour: Double? {
        guard let minutes, minutes > 0 else { return nil }
        return iskValue / Double(minutes) * 60
    }
}

struct RunLedgerSummary: Sendable {
    let count: Int
    let total: Double
    let best: Double
    /// Mean ISK/hour across runs that recorded a duration.
    let avgPerHour: Double?

    static let empty = RunLedgerSummary(count: 0, total: 0, best: 0, avgPerHour: nil)
}

/// UserDefaults-backed store for `ExplorationRun`s. Posts `didChange` so open
/// ledger views refresh.
enum ExplorationRunStore {
    static let defaultsKey = "exploration.runLog.v1"
    static let didChange = Notification.Name("exploration.runLog.didChange")

    static func all() -> [ExplorationRun] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let runs = try? JSONDecoder().decode([ExplorationRun].self, from: data)
        else { return [] }
        return runs.sorted { $0.date > $1.date }
    }

    static func runs(forSite siteID: String) -> [ExplorationRun] {
        all().filter { $0.siteID == siteID }
    }

    static func add(_ run: ExplorationRun) {
        var runs = all()
        runs.append(run)
        persist(runs)
    }

    static func remove(id: UUID) {
        persist(all().filter { $0.id != id })
    }

    static func summary(forSite siteID: String) -> RunLedgerSummary {
        let runs = runs(forSite: siteID)
        guard !runs.isEmpty else { return .empty }
        let total = runs.reduce(0) { $0 + $1.iskValue }
        let best = runs.map(\.iskValue).max() ?? 0
        let perHour = runs.compactMap(\.iskPerHour)
        let avgPerHour = perHour.isEmpty ? nil : perHour.reduce(0, +) / Double(perHour.count)
        return RunLedgerSummary(count: runs.count, total: total, best: best, avgPerHour: avgPerHour)
    }

    private static func persist(_ runs: [ExplorationRun]) {
        if let data = try? JSONEncoder().encode(runs) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

// MARK:  Helpers

func romanNumeral(_ n: Int) -> String {
    switch n {
    case ...0: return "0"
    case 1: return "I"
    case 2: return "II"
    case 3: return "III"
    case 4: return "IV"
    case 5: return "V"
    default: return "\(n)"
    }
}
