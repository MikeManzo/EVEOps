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

/// One collapsible group in the Assets list — a station/type name plus its stacks.
/// Value type so it can be built off the main actor and handed back for rendering.
nonisolated struct AssetSection: Identifiable, Hashable, Sendable {
    let key: String
    let items: [ResolvedAsset]

    var id: String { key }
    var count: Int { items.count }
}

nonisolated extension ResolvedAsset {
    var typeNameFolded: String { typeName.lowercased() }
    var locationNameFolded: String { locationName.lowercased() }
}

/// Pure filter → group → sort for the Assets browser. No main-actor state, so callers
/// run it inside `Task.detached` to keep the "Group by" toggle and search off the UI thread.
nonisolated func buildAssetSections(
    from assets: [ResolvedAsset],
    search: String,
    groupMode: AssetGroupMode
) -> [AssetSection] {
    let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    let filtered: [ResolvedAsset]
    if needle.isEmpty {
        filtered = assets
    } else {
        filtered = assets.filter {
            $0.typeNameFolded.contains(needle) || $0.locationNameFolded.contains(needle)
        }
    }

    let key: (ResolvedAsset) -> String =
        groupMode == .station ? { $0.locationName } : { $0.typeName }

    return Dictionary(grouping: filtered, by: key)
        .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        .map { AssetSection(key: $0.key, items: $0.value) }
}
