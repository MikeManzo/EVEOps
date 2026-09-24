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

/// One NPC-station service as ESI reports it (`services` on `/universe/stations/{id}/`),
/// with the label, symbol and category the Station Browser shows for it. The single
/// source for both the browser list and the station detail panel.
///
/// Icons are deliberately monochrome: color is reserved for meaning (security status,
/// selection), so a row of services reads as a quiet glyph strip rather than confetti.
nonisolated struct StationService: Identifiable, Hashable {
    let key: String
    let label: LocalizedStringKey
    let symbol: String
    let category: Category

    var id: String { key }

    static func == (lhs: StationService, rhs: StationService) -> Bool { lhs.key == rhs.key }
    func hash(into hasher: inout Hasher) { hasher.combine(key) }

    enum Category: Int, CaseIterable, Identifiable {
        case trade, industry, ship, pilot, agencies, corporate

        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .trade:     "Trade"
            case .industry:  "Industry"
            case .ship:      "Ship Services"
            case .pilot:     "Pilot Services"
            case .agencies:  "Agencies & Missions"
            case .corporate: "Corporate"
            }
        }
    }

    /// Services worth surfacing on a list row — the ones pilots pick a station for.
    /// Order is the order they appear in the row.
    static let keyServiceKeys: [String] = [
        "market", "loyalty-point-store", "cloning", "repair-facilities",
        "fitting", "factory", "labratory", "reprocessing-plant"
    ]

    /// Services offered as browser filters.
    static let filterKeys: [String] = [
        "market", "loyalty-point-store", "cloning", "repair-facilities",
        "fitting", "factory", "labratory", "reprocessing-plant", "office-rental"
    ]

    /// Present at (nearly) every station or long retired from the game — never shown.
    private static let hiddenKeys: Set<String> = ["docking", "news", "gambling", "interbus"]

    private static let catalog: [String: StationService] = {
        let all: [StationService] = [
            .init(key: "market",                label: "Market",           symbol: "cart",                         category: .trade),
            .init(key: "stock-exchange",        label: "Stock Exchange",   symbol: "arrow.left.arrow.right",       category: .trade),
            .init(key: "loyalty-point-store",   label: "LP Store",         symbol: "medal",                        category: .trade),
            .init(key: "black-market",          label: "Black Market",     symbol: "eye.slash",                    category: .trade),
            .init(key: "factory",               label: "Manufacturing",    symbol: "hammer",                       category: .industry),
            .init(key: "labratory",             label: "Research",         symbol: "flask",                        category: .industry),
            .init(key: "reprocessing-plant",    label: "Reprocessing",     symbol: "arrow.3.trianglepath",         category: .industry),
            .init(key: "refinery",              label: "Refinery",         symbol: "drop",                         category: .industry),
            .init(key: "fitting",               label: "Fitting",          symbol: "wrench.adjustable",            category: .ship),
            .init(key: "repair-facilities",     label: "Repair",           symbol: "wrench.and.screwdriver",       category: .ship),
            .init(key: "insurance",             label: "Insurance",        symbol: "checkmark.shield",             category: .ship),
            .init(key: "paintshop",             label: "Paint Shop",       symbol: "paintbrush",                   category: .ship),
            .init(key: "cloning",               label: "Medical Bay",      symbol: "person.crop.rectangle.stack",  category: .pilot),
            .init(key: "jump-clone-facility",   label: "Jump Clones",      symbol: "person.2",                     category: .pilot),
            .init(key: "surgery",               label: "Surgery",          symbol: "cross.case",                   category: .pilot),
            .init(key: "dna-therapy",           label: "DNA Therapy",      symbol: "waveform.path.ecg",            category: .pilot),
            .init(key: "bounty-missions",       label: "Bounty Office",    symbol: "scope",                        category: .agencies),
            .init(key: "assasination-missions", label: "Assassinations",   symbol: "target",                       category: .agencies),
            .init(key: "courier-missions",      label: "Courier Missions", symbol: "shippingbox",                  category: .agencies),
            .init(key: "navy-offices",          label: "Navy Offices",     symbol: "flag",                         category: .agencies),
            .init(key: "security-offices",      label: "Security Office",  symbol: "lock.shield",                  category: .agencies),
            .init(key: "office-rental",         label: "Offices",          symbol: "building.2",                   category: .corporate),
            .init(key: "storage",               label: "Storage",          symbol: "archivebox",                   category: .corporate),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    }()

    /// The display entry for an ESI service key; unknown keys get a title-cased label so a
    /// new CCP service still shows up sensibly instead of disappearing.
    static func named(_ key: String) -> StationService? {
        if hiddenKeys.contains(key) { return nil }
        if let known = catalog[key] { return known }
        let label = key.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        return .init(key: key, label: LocalizedStringKey(label), symbol: "building", category: .corporate)
    }

    /// Key services a station offers, in row order.
    static func keyServices(of keys: [String]?) -> [StationService] {
        let offered = Set(keys ?? [])
        return keyServiceKeys.filter(offered.contains).compactMap(named)
    }

    /// Every displayable service a station offers, grouped by category in display order.
    static func grouped(_ keys: [String]?) -> [(category: Category, services: [StationService])] {
        let services = (keys ?? []).compactMap(named)
        return Category.allCases.compactMap { category in
            let inCategory = services.filter { $0.category == category }
                .sorted { $0.key < $1.key }
            return inCategory.isEmpty ? nil : (category, inCategory)
        }
    }
}

/// Splits an NPC station name like "Jita IV - Moon 4 - Caldari Navy Assembly Plant" into
/// the parts a row needs, given the system it's in.
nonisolated struct StationNameParts {
    /// "Caldari Navy Assembly Plant"
    let facility: String
    /// "IV · Moon 4"
    let orbit: String

    init(stationName: String, systemName: String) {
        let parts = stationName.components(separatedBy: " - ")
        guard parts.count >= 2 else {
            facility = stationName
            orbit = ""
            return
        }
        facility = parts.last ?? stationName
        var orbitParts = parts.dropLast().map { $0 }
        if let first = orbitParts.first, first.hasPrefix(systemName) {
            let planet = first.dropFirst(systemName.count).trimmingCharacters(in: .whitespaces)
            orbitParts[0] = planet.isEmpty ? first : planet
        }
        orbit = orbitParts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
