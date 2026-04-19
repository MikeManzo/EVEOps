import SwiftUI

struct ColonyDetailView: View {
    let characterID: Int
    let colony: ResolvedColony

    @Environment(AccountManager.self) private var accountManager
    @Environment(\.dismiss) private var dismiss

    @State private var layout: ESIColonyLayout?
    @State private var isLoading = true
    @State private var error: String?
    @State private var typeNames: [Int: String] = [:]
    @State private var schematics: [Int: ESIPlanetSchematic] = [:]
    @State private var now = Date()

    private var extractors: [ESIPlanetPin] {
        layout?.pins.filter { $0.extractorDetails != nil } ?? []
    }
    private var factories: [ESIPlanetPin] {
        layout?.pins.filter { $0.factoryDetails != nil } ?? []
    }
    private var otherPins: [ESIPlanetPin] {
        layout?.pins.filter { $0.extractorDetails == nil && $0.factoryDetails == nil } ?? []
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading colony…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMsg = error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                                          description: Text(errorMsg))
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            statsBar
                            if !extractors.isEmpty { extractorsSection }
                            if !factories.isEmpty { factoriesSection }
                            if !otherPins.isEmpty { storageSection }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("\(colony.systemName) — \(colony.planetType.capitalized)")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task { await load() }
        .task(id: "timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }

    // MARK:  Stats Bar

    private var statsBar: some View {
        HStack(spacing: 0) {
            statTile("Pins", value: "\(layout?.pins.count ?? 0)", icon: "circle.fill", color: .blue)
            Divider().frame(height: 36)
            statTile("Links", value: "\(layout?.links.count ?? 0)", icon: "link", color: .teal)
            Divider().frame(height: 36)
            statTile("Routes", value: "\(layout?.routes.count ?? 0)", icon: "arrow.triangle.swap", color: .green)
            Divider().frame(height: 36)
            statTile("Upgrade", value: "Lvl \(colony.upgradeLevel)", icon: "star.fill", color: .orange)
            Divider().frame(height: 36)
            statTile("Updated", value: relativeTime(colony.lastUpdate), icon: "clock", color: colony.isStale ? .red : .secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statTile(_ label: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(color).font(.callout)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK:  Extractors

    private var extractorsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Extractors (\(extractors.count))", systemImage: "arrow.down.to.line.circle.fill")
                .font(.headline)
                .foregroundStyle(.cyan)

            ForEach(extractors) { pin in
                extractorRow(pin)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func extractorRow(_ pin: ESIPlanetPin) -> some View {
        let details = pin.extractorDetails!
        let productName = details.productTypeId.flatMap { typeNames[$0] } ?? (details.productTypeId.map { "Type #\($0)" } ?? "Unknown")
        let isExpired = pin.expiryTime.map { $0 < now } ?? true

        return HStack(spacing: 12) {
            AsyncImage(url: details.productTypeId.flatMap { EVEImageURL.typeIcon($0, size: 64) }) { img in
                img.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(productName).font(.subheadline.bold())
                HStack(spacing: 12) {
                    if let cycle = details.cycleTime {
                        Label("\(cycle / 60)m cycle", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let qty = details.qtyPerCycle {
                        Label("\(qty.formatted())/cycle", systemImage: "cube.fill")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Label("\(details.heads.count) heads", systemImage: "mappin.circle.fill")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let expiry = pin.expiryTime {
                    if isExpired {
                        Label("Expired", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.bold()).foregroundStyle(.red)
                    } else {
                        Text("Expires in")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(timeUntil(expiry))
                            .font(.caption.bold().monospacedDigit()).foregroundStyle(.green)
                    }
                } else {
                    Text("Inactive")
                        .font(.caption.bold()).foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK:  Factories

    private var factoriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Processors (\(factories.count))", systemImage: "gearshape.2.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            ForEach(factories) { pin in
                factoryRow(pin)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func factoryRow(_ pin: ESIPlanetPin) -> some View {
        let pinName = typeNames[pin.typeId] ?? "Factory"
        let schematicID = pin.schematicId ?? pin.factoryDetails?.schematicId
        let schematic = schematicID.flatMap { schematics[$0] }

        return HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeIcon(pin.typeId, size: 64)) { img in
                img.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(pinName).font(.subheadline.bold())
                if let schematic {
                    let inputs = schematic.pins.filter(\.isInput)
                    let outputs = schematic.pins.filter { !$0.isInput }
                    HStack(spacing: 4) {
                        ForEach(inputs, id: \.typeId) { p in
                            Text("\(p.quantity)x \(typeNames[p.typeId] ?? "#\(p.typeId)")")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        ForEach(outputs, id: \.typeId) { p in
                            Text("\(p.quantity)x \(typeNames[p.typeId] ?? "#\(p.typeId)")")
                                .font(.caption2).foregroundStyle(.green)
                        }
                    }
                    Text("\(schematic.cycleTime / 60)m cycle")
                        .font(.caption2).foregroundStyle(.secondary)
                } else if let sID = schematicID {
                    Text("Schematic #\(sID)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Content indicator
            if let contents = pin.contents, !contents.isEmpty {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Storage")
                        .font(.caption2).foregroundStyle(.secondary)
                    ForEach(contents.prefix(2), id: \.typeId) { content in
                        Text("\(content.amount.formatted())x \(typeNames[content.typeId] ?? "#\(content.typeId)")")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK:  Storage / Launchpads

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage & Command (\(otherPins.count))", systemImage: "archivebox.fill")
                .font(.headline)
                .foregroundStyle(.purple)

            ForEach(otherPins) { pin in
                storageRow(pin)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func storageRow(_ pin: ESIPlanetPin) -> some View {
        let pinName = typeNames[pin.typeId] ?? "Pin #\(pin.typeId)"
        let contents = pin.contents ?? []

        return HStack(spacing: 12) {
            AsyncImage(url: EVEImageURL.typeIcon(pin.typeId, size: 64)) { img in
                img.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(pinName).font(.subheadline.bold())
                if contents.isEmpty {
                    Text("Empty").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(contents.prefix(3), id: \.typeId) { content in
                        Text("\(content.amount.formatted())x \(typeNames[content.typeId] ?? "Type #\(content.typeId)")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if contents.count > 3 {
                        Text("+\(contents.count - 3) more…")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK:  Load

    private func load() async {
        guard let account = accountManager.accounts.first(where: { $0.characterID == characterID }) else {
            error = "Account not found"
            isLoading = false
            return
        }
        do {
            let token = try await accountManager.validToken(for: account)
            let fetched: ESIColonyLayout = try await ESIClient.shared.fetch(
                "/characters/\(characterID)/planets/\(colony.planetId)/", token: token
            )
            layout = fetched

            // Collect all type IDs for batch resolution
            var typeIDs: Set<Int> = []
            for pin in fetched.pins {
                typeIDs.insert(pin.typeId)
                if let det = pin.extractorDetails, let pid = det.productTypeId { typeIDs.insert(pid) }
                if let contents = pin.contents { contents.forEach { typeIDs.insert($0.typeId) } }
            }
            let resolved = await UniverseCache.shared.types(ids: Array(typeIDs))
            var names: [Int: String] = [:]
            for (id, type_) in resolved { names[id] = type_.name }
            typeNames = names

            // Fetch schematics
            let schematicIDs = Set(fetched.pins.compactMap { $0.schematicId ?? $0.factoryDetails?.schematicId })
            var fetchedSchematics: [Int: ESIPlanetSchematic] = [:]
            await withTaskGroup(of: (Int, ESIPlanetSchematic?).self) { group in
                for sid in schematicIDs {
                    group.addTask {
                        let s: ESIPlanetSchematic? = try? await ESIClient.shared.fetch("/universe/schematics/\(sid)/")
                        return (sid, s)
                    }
                }
                for await (sid, s) in group {
                    if let s { fetchedSchematics[sid] = s }
                }
            }
            // Resolve schematic pin type names
            var schematicTypeIDs: Set<Int> = []
            for s in fetchedSchematics.values { s.pins.forEach { schematicTypeIDs.insert($0.typeId) } }
            let schematicTypes = await UniverseCache.shared.types(ids: Array(schematicTypeIDs))
            for (id, t) in schematicTypes { names[id] = t.name }
            typeNames = names
            schematics = fetchedSchematics

        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK:  Helpers

    private func timeUntil(_ date: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Expired" }
        let total = Int(interval)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
