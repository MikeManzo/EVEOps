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

// MARK:  Tree Data Models

private let treeAttrPairs: [(skillAttr: Int, levelAttr: Int)] = [
    (182, 277), (183, 278), (184, 279),
    (1285, 1289), (1286, 1290), (1287, 1291)
]

private enum SkillNodeStatus: Equatable {
    case root, met, partial, missing, noChar

    var color: Color {
        switch self {
        case .root:    return .accentColor
        case .met:     return .green
        case .partial: return .orange
        case .missing: return .red
        case .noChar:  return Color(.systemGray)
        }
    }
}

private struct SkillNode: Identifiable {
    let id: Int             // typeId; -1 = root item
    let name: String
    let requiredLevel: Int  // 0 for root
    let trainedLevel: Int
    var column: Int
    var row: Int
    var position: CGPoint

    func status(hasChar: Bool) -> SkillNodeStatus {
        if id == -1 { return .root }
        if !hasChar { return .noChar }
        if trainedLevel >= requiredLevel { return .met }
        if trainedLevel > 0 { return .partial }
        return .missing
    }
}

private struct SkillEdge {
    let fromId: Int
    let toId: Int
}

// Mutable accumulator used during the async recursive tree walk.
private final class SkillTreeBuildState {
    var nodeData: [Int: (name: String, requiredLevel: Int, trainedLevel: Int)] = [:]
    var edges: [(from: Int, to: Int)] = []
    var visited: Set<Int> = []
}

// MARK:  Shared Helpers

private func skillRoman(_ n: Int) -> String {
    let t = ["0", "I", "II", "III", "IV", "V"]
    return n < t.count ? t[n] : "\(n)"
}

// MARK:  Layout Constants

private let nodeW: CGFloat = 182
private let nodeH: CGFloat = 66
private let depthSpacing: CGFloat = 108  // vertical: depth level center-to-center
private let siblingSpacing: CGFloat = 202 // horizontal: sibling center-to-center
private let treePad: CGFloat = 36

// MARK:  ItemSkillTreeView

struct ItemSkillTreeView: View {
    /// Trained skill levels keyed by typeId. Pass nil when no character is logged in.
    let characterSkills: [Int: Int]?
    /// Called when the user taps + on a skill node or "Add All to Plan".
    var onAddToPlan: ((SkillPlanItem) -> Void)?

    @Environment(AccountManager.self) private var accountManager

    // Search
    @State private var searchText = ""
    @State private var searchResults: [(id: Int, name: String)] = []
    @State private var isSearching = false
    @State private var searchDebounce: Task<Void, Never>?

    // Selected item
    @State private var selectedTypeId: Int?
    @State private var selectedTypeName = ""

    // Tree state
    @State private var nodes: [SkillNode] = []
    @State private var edges: [SkillEdge] = []
    @State private var isBuilding = false
    @State private var treeMessage: String?

    // Per-node NSView anchors for NSPopover (class avoids SwiftUI re-render loops)
    @State private var nodeViewStore = NodeViewStore()

    private var hasChar: Bool { characterSkills != nil }

    var body: some View {
        VStack(spacing: 0) {
            itemSearchBar
                .padding(10)
            Divider()
            treeContent
        }
    }

    // MARK:  Search Bar

    private var itemSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search for a ship or module…", text: $searchText)
                .textFieldStyle(.plain)
                .onChange(of: searchText) { _, new in triggerSearch(new) }
                .onSubmit {
                    if let first = searchResults.first { selectItem(first.id, name: first.name) }
                }

            if isSearching {
                ProgressView().controlSize(.mini)
            } else if !searchText.isEmpty {
                Button { clearItem() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK:  Tree Content

    @ViewBuilder
    private var treeContent: some View {
        if isSearching {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !searchResults.isEmpty && selectedTypeId == nil {
            // Show search results as a proper inline list — no floating overlay.
            searchResultsList
        } else if isBuilding {
            VStack(spacing: 10) {
                ProgressView()
                Text("Resolving skill tree…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let msg = treeMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2).foregroundStyle(.tertiary)
                Text(msg)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if nodes.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                scrollableTree
                footerBar
            }
        }
    }

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults, id: \.id) { result in
                    Button { selectItem(result.id, name: result.name) } label: {
                        HStack(spacing: 12) {
                            AsyncImage(url: EVEImageURL.typeIcon(result.id, size: 64)) { phase in
                                if let img = phase.image {
                                    img.resizable()
                                        .frame(width: 64, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                } else {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(.quaternary)
                                        .frame(width: 64, height: 64)
                                }
                            }
                            Text(result.name)
                                .font(.title3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 54)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 42)).foregroundStyle(.tertiary)
            Text("Search for an item to see its skill tree")
                .font(.subheadline).foregroundStyle(.secondary)
            Text("Ships, modules, drones — any item with skill requirements")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK:  Scrollable Tree Canvas

    private var computedCanvasSize: CGSize {
        guard !nodes.isEmpty else { return CGSize(width: 400, height: 250) }
        let maxX = nodes.map { $0.position.x + nodeW / 2 }.max() ?? 400
        let maxY = nodes.map { $0.position.y + nodeH / 2 }.max() ?? 250
        return CGSize(width: maxX + treePad, height: maxY + treePad)
    }

    private var scrollableTree: some View {
        GeometryReader { geo in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                let size = computedCanvasSize
                ZStack(alignment: .topLeading) {
                    Canvas { ctx, _ in renderEdges(ctx) }
                        .allowsHitTesting(false)

                    Color.clear
                        .frame(width: size.width, height: size.height)

                    ForEach(nodes) { node in
                        nodeCard(for: node)
                            .frame(width: nodeW, height: nodeH)
                            .overlay(NodeAnchorCapture(store: nodeViewStore, nodeId: node.id))
                            .position(node.position)
                    }
                }
                .frame(width: size.width, height: size.height)
                // When the tree is smaller than the available area, expand
                // the scroll content to fill it so the ZStack centers naturally.
                .frame(minWidth: geo.size.width, minHeight: geo.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK:  Edge Rendering

    private func renderEdges(_ ctx: GraphicsContext) {
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for edge in edges {
            guard let from = nodeMap[edge.fromId], let to = nodeMap[edge.toId] else { continue }
            let edgeColor = to.status(hasChar: hasChar).color
            // Top-down layout: exit from bottom-center of parent, enter top-center of child.
            let sx = from.position.x
            let sy = from.position.y + nodeH / 2
            let ex = to.position.x
            let ey = to.position.y - nodeH / 2
            let bend = min(CGFloat(36), (ey - sy) * 0.4)
            var path = Path()
            path.move(to: CGPoint(x: sx, y: sy))
            path.addCurve(
                to: CGPoint(x: ex, y: ey),
                control1: CGPoint(x: sx, y: sy + bend),
                control2: CGPoint(x: ex, y: ey - bend)
            )
            ctx.stroke(path, with: .color(edgeColor.opacity(0.58)), lineWidth: 1.5)
        }
    }

    // MARK:  Node Card

    @ViewBuilder
    private func nodeCard(for node: SkillNode) -> some View {
        let s = node.status(hasChar: hasChar)
        let isRoot = node.id == -1

        HStack(spacing: 0) {
            // Colored left accent strip
            Rectangle()
                .fill(s.color)
                .frame(width: 4)

            HStack(spacing: 7) {
                // Item render for root (with icon fallback), skill icon for skill nodes
                if isRoot {
                    TypeImageView(typeId: selectedTypeId ?? 0,
                                  size: 40, cornerRadius: 7)
                } else {
                    AsyncImage(url: EVEImageURL.typeIcon(node.id, size: 64)) { phase in
                        if let img = phase.image {
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary)
                                .frame(width: 28, height: 28)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(node.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(isRoot ? 1 : 2)
                        .minimumScaleFactor(0.85)

                    if !isRoot {
                        HStack(spacing: 2) {
                            ForEach(1...5, id: \.self) { lvl in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(lvl <= node.trainedLevel
                                          ? s.color
                                          : Color.white.opacity(0.10))
                                    .frame(width: 11, height: 7)
                            }
                            Text("→ \(skillRoman(node.requiredLevel))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(s.color)
                                .padding(.leading, 2)
                        }
                    } else {
                        Text("Required skills")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                // Add-to-plan button for unmet/partial skills only
                if !isRoot, (s == .partial || s == .missing), let add = onAddToPlan {
                    Button {
                        add(SkillPlanItem(
                            skillId: node.id,
                            skillName: node.name,
                            fromLevel: node.trainedLevel,
                            targetLevel: node.requiredLevel
                        ))
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(s.color.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .help("Add \(node.name) \(skillRoman(node.requiredLevel)) to skill plan")
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(s.color.opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        .contextMenu {
            let typeIdForMarket = isRoot ? (selectedTypeId ?? -1) : node.id
            let nameForMarket   = isRoot ? selectedTypeName : node.name

            Button {
                showPopover(for: node)
            } label: {
                Label("View Details", systemImage: "info.circle")
            }

            Divider()

            if typeIdForMarket > 0 {
                Button {
                    WindowService.shared.showGalaxySearch(typeId: typeIdForMarket, typeName: nameForMarket)
                } label: {
                    Label("Find on Market", systemImage: "chart.line.uptrend.xyaxis")
                }
            }

            if !isRoot, (s == .partial || s == .missing), let add = onAddToPlan {
                Divider()
                Button {
                    add(SkillPlanItem(
                        skillId: node.id,
                        skillName: node.name,
                        fromLevel: node.trainedLevel,
                        targetLevel: node.requiredLevel
                    ))
                } label: {
                    Label("Add to Skill Plan", systemImage: "plus.circle")
                }
            }

            Divider()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(nameForMarket, forType: .string)
            } label: {
                Label("Copy Name", systemImage: "doc.on.doc")
            }
        }
    }

    // MARK:  Footer Bar

    @ViewBuilder
    private var footerBar: some View {
        let unmet = nodes.filter { n in
            let s = n.status(hasChar: hasChar)
            return s == .missing || s == .partial
        }
        if !unmet.isEmpty {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange).font(.caption)
                Text("\(unmet.count) skill\(unmet.count == 1 ? "" : "s") need training")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let add = onAddToPlan {
                    Button("Add All to Plan") {
                        for node in unmet {
                            add(SkillPlanItem(
                                skillId: node.id,
                                skillName: node.name,
                                fromLevel: node.trainedLevel,
                                targetLevel: node.requiredLevel
                            ))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK:  Search Logic

    private func triggerSearch(_ query: String) {
        searchDebounce?.cancel()
        // selectItem sets searchText = name programmatically; skip the resulting onChange
        // so we don't clear the selection and re-run a search immediately after selection.
        if selectedTypeId != nil && query == selectedTypeName { return }
        // If the user cleared or shortened the text while an item is shown, keep the tree.
        guard query.count >= 3 else {
            if query.isEmpty { searchResults = [] }
            return
        }
        // A new search means we've left the previously selected item.
        selectedTypeId = nil
        nodes = []; edges = []; treeMessage = nil
        searchDebounce = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(query)
        }
    }

    private func runSearch(_ query: String) async {
        isSearching = true
        defer { isSearching = false }

        let lower = query.lowercased()
        struct SearchResp: Decodable { let inventoryType: [Int]? }
        struct NameEntry: Decodable { let id: Int; let name: String }

        var candidates: [(id: Int, name: String)] = []

        if let account = accountManager.selectedAccount,
           let token = try? await accountManager.validToken(for: account) {
            let resp: SearchResp? = try? await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/search/", token: token,
                queryItems: [
                    URLQueryItem(name: "categories", value: "inventory_type"),
                    URLQueryItem(name: "search", value: query),
                    URLQueryItem(name: "strict", value: "false")
                ]
            )
            let ids = Array((resp?.inventoryType ?? []).prefix(100))
            guard !ids.isEmpty else { searchResults = []; return }
            let names: [NameEntry] = (try? await ESIClient.shared.post("/universe/names/", body: ids)) ?? []
            candidates = names.map { (id: $0.id, name: $0.name) }
        } else {
            struct IDResp: Decodable { let inventoryTypes: [ESIIDName]? }
            let resp: IDResp? = try? await ESIClient.shared.post("/universe/ids/", body: [query])
            candidates = (resp?.inventoryTypes ?? []).map { (id: $0.id, name: $0.name) }
        }

        guard !candidates.isEmpty else { searchResults = []; return }

        // Filter to only items that have at least one skill prerequisite in their dogma attributes.
        // This definitively excludes SKINs, apparel, commodities, and anything else with no training requirements.
        let skillAttrIds = Set(treeAttrPairs.map(\.skillAttr))
        let typeMap = await UniverseCache.shared.types(ids: candidates.map(\.id))
        let filtered = candidates.filter { item in
            guard let attrs = typeMap[item.id]?.dogmaAttributes else { return false }
            return attrs.contains { skillAttrIds.contains($0.attributeId) && $0.value > 0 }
        }

        searchResults = filtered.sorted {
            let aL = $0.name.lowercased(), bL = $1.name.lowercased()
            if (aL == lower) != (bL == lower) { return aL == lower }
            if aL.hasPrefix(lower) != bL.hasPrefix(lower) { return aL.hasPrefix(lower) }
            return aL < bL
        }
    }

    private func selectItem(_ id: Int, name: String) {
        selectedTypeId = id
        selectedTypeName = name
        searchText = name
        searchResults = []
        Task { await buildSkillTree(for: id) }
    }

    private func clearItem() {
        searchText = ""; searchResults = []
        selectedTypeId = nil; selectedTypeName = ""
        nodes = []; edges = []; treeMessage = nil
    }

    // MARK:  Tree Building

    private func buildSkillTree(for typeId: Int) async {
        isBuilding = true
        treeMessage = nil
        nodes = []; edges = []
        defer { isBuilding = false }

        // Fetch root item's dogma attributes
        let rootAttrs: [ESIDogmaAttribute]
        if let cached = await UniverseCache.shared.types(ids: [typeId])[typeId],
           let a = cached.dogmaAttributes, !a.isEmpty {
            rootAttrs = a
        } else if let fetched: ESIType = try? await ESIClient.shared.fetch(
            "/universe/types/\(typeId)/", bypassCache: true),
                  let a = fetched.dogmaAttributes {
            rootAttrs = a
        } else {
            treeMessage = "Could not load item data."
            return
        }

        guard !Task.isCancelled else { return }

        let state = SkillTreeBuildState()
        state.nodeData[-1] = (name: selectedTypeName, requiredLevel: 0, trainedLevel: 0)
        await traversePrereqs(parentId: -1, attrs: rootAttrs, state: state)

        guard !Task.isCancelled else { return }

        guard !state.edges.isEmpty else {
            treeMessage = "This item has no skill requirements."
            return
        }

        // Assign columns: longest path from root via iterative relaxation.
        // This ensures shared prerequisite nodes land to the right of every
        // node that depends on them (column = max incoming edge source + 1).
        var colMap: [Int: Int] = [-1: 0]
        var stable = false
        while !stable {
            stable = true
            for edge in state.edges {
                let parentCol = colMap[edge.from] ?? 0
                let wanted = parentCol + 1
                if (colMap[edge.to] ?? 0) < wanted {
                    colMap[edge.to] = wanted
                    stable = false
                }
            }
        }

        // Deduplicate edges (same skill can be a prereq of multiple parents).
        var seenEdges = Set<String>()
        let uniqueEdges = state.edges.filter { seenEdges.insert("\($0.from)-\($0.to)").inserted }

        // Group node IDs by column.
        var byCol: [Int: [Int]] = [:]
        for (id, col) in colMap { byCol[col, default: []].append(id) }

        // Within each column sort alphabetically; root node is always first.
        for key in byCol.keys {
            byCol[key]!.sort { a, b in
                if a == -1 { return true }
                if b == -1 { return false }
                return (state.nodeData[a]?.name ?? "") < (state.nodeData[b]?.name ?? "")
            }
        }

        // Compute pixel positions for top-down layout.
        // Depth (column value) drives Y; sibling index (row) drives X.
        // Narrower depth levels are horizontally centered relative to the widest level.
        let maxSiblings = byCol.values.map(\.count).max() ?? 1
        let totalW = CGFloat(maxSiblings - 1) * siblingSpacing

        var layoutNodes: [SkillNode] = []
        for (col, ids) in byCol {
            let sibCount = ids.count
            let levelW = CGFloat(sibCount - 1) * siblingSpacing
            let startX = treePad + nodeW / 2 + (totalW - levelW) / 2
            let y = treePad + nodeH / 2 + CGFloat(col) * depthSpacing
            for (row, id) in ids.enumerated() {
                guard let data = state.nodeData[id] else { continue }
                layoutNodes.append(SkillNode(
                    id: id,
                    name: data.name,
                    requiredLevel: data.requiredLevel,
                    trainedLevel: data.trainedLevel,
                    column: col, row: row,
                    position: CGPoint(x: startX + CGFloat(row) * siblingSpacing, y: y)
                ))
            }
        }

        nodes = layoutNodes.sorted { $0.column < $1.column }
        edges = uniqueEdges.map { SkillEdge(fromId: $0.from, toId: $0.to) }
    }

    // Recursive async walk of the skill prerequisite graph.
    // Uses SkillTreeBuildState as a shared mutable accumulator so we avoid
    // threading large dictionaries through inout parameters across await points.
    private func traversePrereqs(
        parentId: Int,
        attrs: [ESIDogmaAttribute],
        state: SkillTreeBuildState
    ) async {
        let attrMap = Dictionary(attrs.map { ($0.attributeId, $0.value) },
                                 uniquingKeysWith: { a, _ in a })
        var prereqs: [(id: Int, level: Int)] = []
        for pair in treeAttrPairs {
            guard let rawSkill = attrMap[pair.skillAttr],
                  let rawLevel = attrMap[pair.levelAttr] else { continue }
            let sid = Int(rawSkill), lvl = Int(rawLevel)
            guard sid > 0, lvl > 0 else { continue }
            prereqs.append((sid, lvl))
        }
        guard !prereqs.isEmpty else { return }

        // Batch-fetch ESIType for skills not yet visited.
        let newIds = prereqs.map(\.id).filter { !state.visited.contains($0) }
        state.visited.formUnion(newIds)

        var typeMap: [Int: ESIType] = [:]
        if !newIds.isEmpty {
            let cached = await UniverseCache.shared.types(ids: newIds)
            for (id, t) in cached where t.dogmaAttributes != nil { typeMap[id] = t }
            // Fetch dogma for any skill whose cached entry is missing attributes.
            for id in newIds where typeMap[id] == nil {
                if let t: ESIType = try? await ESIClient.shared.fetch(
                    "/universe/types/\(id)/", bypassCache: true) {
                    typeMap[id] = t
                }
            }
        }

        for (sid, lvl) in prereqs {
            state.edges.append((from: parentId, to: sid))

            if state.nodeData[sid] == nil {
                state.nodeData[sid] = (
                    name: typeMap[sid]?.name ?? "Skill \(sid)",
                    requiredLevel: lvl,
                    trainedLevel: characterSkills?[sid] ?? 0
                )
            }

            // Recurse into this skill's own prerequisites.
            if let skillAttrs = typeMap[sid]?.dogmaAttributes {
                await traversePrereqs(parentId: sid, attrs: skillAttrs, state: state)
            }
        }
    }

    // MARK: NSPopover Presentation

    private func showPopover(for node: SkillNode) {
        // The NodeAnchorCapture overlay gives us a PassthroughNSView that sits exactly
        // over the node card in the NSView hierarchy. AppKit's show(relativeTo:of:)
        // converts from that view's local space to screen coords automatically —
        // scroll offset, window position, all included for free.
        guard let anchor = nodeViewStore.views[node.id] else { return }

        let edge: NSRectEdge = node.position.x > computedCanvasSize.width / 2 ? .minX : .maxX
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: NodeDetailView(
            node: node,
            isRoot: node.id == -1,
            selectedTypeId: selectedTypeId,
            characterSkills: characterSkills,
            onAddToPlan: onAddToPlan
        ))
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: edge)
    }

}

// MARK: Type Image with Render → Icon Fallback

/// Shows the 3D render image for a type (ships, structures, etc.).
/// Automatically falls back to the flat icon if the render URL returns nothing,
/// which happens for modules, drones, and other non-rendered item types.
private struct TypeImageView: View {
    let typeId: Int
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        AsyncImage(url: EVEImageURL.typeRender(typeId, size: 256)) { phase in
            switch phase {
            case .success(let img):
                img.resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            case .failure:
                AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 64)) { phase2 in
                    if let img = phase2.image {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    } else {
                        placeholder
                    }
                }
            default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(.quaternary)
            .frame(width: size, height: size)
    }
}

// MAR:K NSView Anchor for NSPopover

// Class store — mutating it never triggers a SwiftUI re-render.
private final class NodeViewStore {
    var views: [Int: NSView] = [:]
}

// Overrides hitTest so the overlay is invisible to all mouse events.
// Right-clicks pass straight through to the SwiftUI context menu below.
private final class PassthroughNSView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

// Overlay representable — fills the node card frame, stores its NSView, passes all events.
private struct NodeAnchorCapture: NSViewRepresentable {
    let store: NodeViewStore
    let nodeId: Int
    func makeNSView(context: Context) -> PassthroughNSView { PassthroughNSView() }
    func updateNSView(_ nsView: PassthroughNSView, context: Context) {
        store.views[nodeId] = nsView
    }
}

// MARK: Node Detail Popover

private struct NodeDetailView: View {
    let node: SkillNode
    let isRoot: Bool
    let selectedTypeId: Int?
    let characterSkills: [Int: Int]?
    var onAddToPlan: ((SkillPlanItem) -> Void)?

    @State private var esiType: ESIType?
    @State private var isLoading = true

    private var typeId: Int { isRoot ? (selectedTypeId ?? 0) : node.id }
    private var hasChar: Bool { characterSkills != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else if let desc = esiType?.description, !desc.isEmpty {
                Divider()
                Text(desc)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !isRoot {
                let s = node.status(hasChar: hasChar)
                if (s == .partial || s == .missing), let add = onAddToPlan {
                    Divider()
                    HStack {
                        Spacer()
                        Button("Add to Skill Plan") {
                            add(SkillPlanItem(
                                skillId: node.id,
                                skillName: node.name,
                                fromLevel: node.trainedLevel,
                                targetLevel: node.requiredLevel
                            ))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 280, maxWidth: 400)
        .fixedSize(horizontal: false, vertical: true)
        .task { await loadType() }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            if isRoot {
                TypeImageView(typeId: typeId, size: 56, cornerRadius: 10)
            } else {
                AsyncImage(url: EVEImageURL.typeIcon(node.id, size: 64)) { phase in
                    if let img = phase.image {
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.quaternary)
                            .frame(width: 56, height: 56)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(node.name)
                    .font(.title3)
                    .lineLimit(2)

                if !isRoot {
                    let s = node.status(hasChar: hasChar)
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { lvl in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(lvl <= node.trainedLevel ? s.color : Color.white.opacity(0.15))
                                .frame(width: 16, height: 10)
                        }
                        Text("→ \(skillRoman(node.requiredLevel)) req.")
                            .font(.subheadline)
                            .foregroundStyle(s.color)
                    }
                    Text(statusLabel(for: s))
                        .font(.caption)
                        .foregroundStyle(s.color)
                } else if let type = esiType {
                    HStack(spacing: 10) {
                        if let vol = type.volume {
                            Label(formatVolume(vol), systemImage: "cube.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let mass = type.mass {
                            Label(formatMass(mass), systemImage: "scalemass.fill")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func statusLabel(for s: SkillNodeStatus) -> String {
        switch s {
        case .met:     return "Trained to Level \(node.trainedLevel)"
        case .partial: return "Partial: \(node.trainedLevel) of \(node.requiredLevel) trained"
        case .missing: return "Not trained"
        case .noChar:  return "No character selected"
        default:       return ""
        }
    }

    private func formatVolume(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.2fM m³", v / 1_000_000) }
        if v >= 1_000 { return String(format: "%.1fK m³", v / 1_000) }
        return String(format: "%.1f m³", v)
    }

    private func formatMass(_ m: Double) -> String {
        if m >= 1_000_000_000 { return String(format: "%.2f Tg", m / 1_000_000_000) }
        if m >= 1_000_000 { return String(format: "%.2f Mg", m / 1_000_000) }
        return String(format: "%.0f kg", m)
    }

    private func loadType() async {
        isLoading = true
        defer { isLoading = false }
        if let cached = await UniverseCache.shared.types(ids: [typeId])[typeId],
           cached.description != nil {
            esiType = cached
        } else if let fetched: ESIType = try? await ESIClient.shared.fetch(
            "/universe/types/\(typeId)/", bypassCache: true) {
            esiType = fetched
        }
    }
}

