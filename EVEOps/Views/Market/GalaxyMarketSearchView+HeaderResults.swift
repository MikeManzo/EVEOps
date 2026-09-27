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

extension GalaxyMarketSearchView {
    // MARK:  Header Panel

    var headerPanel: some View {
        VStack(alignment: .leading, spacing: EVESpacing.lg) {
            // Item search + order type + search button
            HStack(spacing: 10) {
                if let typeId = selectedTypeId {
                    TypeImage(typeId: typeId, size: 28, cornerRadius: EVERadius.xs)
                }

                HStack(spacing: EVESpacing.sm) {
                    if selectedTypeId == nil {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    TextField("Search for an item…", text: $itemSearchText).eveFindTarget()
                        .textFieldStyle(.plain)
                        .onChange(of: itemSearchText) { _, v in onItemSearchChanged(v) }
                    if isSearchingItems {
                        ProgressView().controlSize(.mini)
                    } else if !itemSearchText.isEmpty {
                        Button { clearItemSelection() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Clear")
                        .buttonStyle(.plain)
                    }
                }
                .padding(EVESpacing.md)
                .eveCard(cornerRadius: EVERadius.md)
                .frame(maxWidth: 320)

                // Order type picker
                Picker("Order Type", selection: $orderTypeFilter) {
                    Text("Sell").tag(OrderTypeFilter.sell)
                    Text("Buy").tag(OrderTypeFilter.buy)
                    Text("Both").tag(OrderTypeFilter.all)
                }
                .eveSegmentedPicker()
                .labelsHidden()
                .frame(width: 160)
                .help("Choose which order types to search for")

                Button {
                    Task { await performGalaxySearch() }
                } label: {
                    Label("Search Galaxy", systemImage: "magnifyingglass.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
                .help(selectedTypeId == nil ? "Select an item first" : "Search all k-space regions")
            }

            if selectedTypeId != nil {
                SkillRequirementsView(typeId: selectedTypeId, typeInfo: selectedTypeInfo, characterSkills: characterSkillMap)
            }

            // Filters row
            HStack(spacing: 20) {
                Toggle("High-sec stations only", isOn: $highSecOnly)
                    .toggleStyle(.checkbox)
                    .help("Only show orders in systems with security status ≥ 0.5")

                if hasLocation {
                    Divider().frame(height: 16)

                    HStack(spacing: EVESpacing.sm) {
                        Text("Max jumps:")
                            .foregroundStyle(.secondary)
                        Stepper(value: $maxJumps, in: 0...100, step: 5) {
                            Text(maxJumps == 0 ? "Unlimited" : "\(maxJumps)")
                                .font(.subheadline.bold().monospacedDigit())
                                .frame(minWidth: 60, alignment: .leading)
                        }
                    }

                    if maxJumps > 0 {
                        Divider().frame(height: 16)
                        Toggle("High-sec route", isOn: $secureRoute)
                            .toggleStyle(.checkbox)
                            .help("Measure distance only through high-sec systems")
                    }
                } else {
                    Text("Log in a character to enable jump-distance filtering")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.orange)
                }

                Spacer()

                if let msg = waypointMessage {
                    HStack(spacing: 5) {
                        Image(systemName: msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint")
                              ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(msg.hasPrefix("Destination") || msg.hasPrefix("Waypoint")
                                             ? .green : .orange)
                        Text(msg)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
                } else if isComputingJumps {
                    HStack(spacing: EVESpacing.sm) {
                        ProgressView().controlSize(.mini)
                        Text("Computing jump distances…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !orders.isEmpty {
                    orderCountSummary
                }
            }
            .font(.subheadline)
        }
        .padding(EVESpacing.xl)
        .fixedSize(horizontal: false, vertical: true)
    }

    var orderCountSummary: some View {
        HStack(spacing: EVESpacing.md) {
            if sellCount > 0 {
                HStack(spacing: EVESpacing.xs) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("\(sellCount) sell")
                }
            }
            if buyCount > 0 {
                HStack(spacing: EVESpacing.xs) {
                    Circle().fill(Color.orange).frame(width: 6, height: 6)
                    Text("\(buyCount) buy")
                }
            }
            Text("across \(regionsSearched) region\(regionsSearched == 1 ? "" : "s")")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK:  Content Area

    @ViewBuilder
    var contentArea: some View {
        if isSearching {
            searchingView
        } else if !itemSearchResults.isEmpty && selectedTypeId == nil {
            itemSearchList
        } else if !orders.isEmpty {
            resultsTable
        } else {
            emptyStateView
        }
    }

    // MARK:  Item Search List

    var itemSearchList: some View {
        List(itemSearchResults, id: \.id) { result in
            Button {
                selectedTypeId = result.typeId
                selectedTypeName = result.name
                itemSearchText = result.name
                itemSearchResults = []
                Task {
                    selectedTypeInfo = await UniverseCache.shared.type(id: result.typeId)
                }
            } label: {
                HStack(spacing: 14) {
                    TypeImage(typeId: result.typeId, size: 48, cornerRadius: EVERadius.sm)
                    Text(result.name).font(.title3)
                    Spacer()
                }
                .padding(.vertical, EVESpacing.xs)
            }
            .buttonStyle(.plain)
            .eveContextMenu(.item(typeID: result.typeId, name: result.name))
        }
        .listStyle(.plain)
    }

    // MARK:  Searching Progress

    var searchingView: some View {
        VStack(spacing: EVESpacing.xl) {
            if totalRegions > 0 {
                ProgressView(value: Double(min(regionsSearched, totalRegions)), total: Double(totalRegions))
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 420)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 420)
            }

            Text(totalRegions > 0
                 ? "Searching region \(regionsSearched) of \(totalRegions)…"
                 : "Loading region list…")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Cancel") {
                galaxyTask?.cancel()
                isSearching = false
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK:  Results Table

    var resultsTable: some View {
        Table(sortedOrders, selection: $selectedOrderIDs, sortOrder: $sortOrder) {
            // Side — only when showing both order types.
            if orderTypeFilter == .all {
                TableColumn("Type", value: \.side) { row in
                    EVEChip(Text(row.side), tint: row.isBuyOrder ? .orange : .green)
                }
                .width(52)
            }

            TableColumn("Price", value: \.price) { row in
                Text(EVEFormatters.formatISK(row.price))
                    .font(.body.monospacedDigit().bold())
                    .foregroundStyle(row.isBuyOrder ? .orange : .green)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 110, ideal: 140)

            TableColumn("Qty", value: \.quantity) { row in
                Text(formatCount(row.quantity))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 70)

            TableColumn("Station / System", value: \.locationName) { row in
                VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                    Text(row.locationName)
                        .lineLimit(1)
                        .eveTruncationHelp(row.locationName)
                    HStack(spacing: EVESpacing.xs) {
                        Text(row.systemName)
                        if row.isBuyOrder {
                            Text("·")
                            Text(formatRange(row.order.range))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .width(min: 220, ideal: 360)

            TableColumn("Region", value: \.regionName) { row in
                Text(row.regionName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 110)

            TableColumn("Sec", value: \.securityStatus) { row in
                EVESecurityBadge(status: row.securityStatus, compact: true)
                    .frame(maxWidth: .infinity)
            }
            .width(48)

            if hasLocation {
                TableColumn("Jumps", value: \.jumpsSortKey) { row in
                    jumpBadge(jumps: row.jumps)
                        .frame(maxWidth: .infinity)
                }
                .width(64)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: GalaxyOrder.ID.self) { ids in
            if let id = ids.first, let row = sortedOrders.first(where: { $0.id == id }) {
                let destId = row.order.locationId
                Button("Set Destination: \(row.locationName)", systemImage: "location.fill") {
                    Task { await setWaypoint(destinationId: destId, clear: true) }
                }
                Button("Add Waypoint: \(row.locationName)", systemImage: "plus.circle") {
                    Task { await setWaypoint(destinationId: destId, clear: false) }
                }
                Divider()
                Button("Copy", systemImage: "doc.on.doc") {
                    let text = sortedOrders.filter { ids.contains($0.id) }.map(\.copyText).joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
        } primaryAction: { ids in
            // Double-click a row: set it as the autopilot destination.
            guard ids.count == 1, let id = ids.first,
                  let row = sortedOrders.first(where: { $0.id == id }) else { return }
            Task { await setWaypoint(destinationId: row.order.locationId, clear: true) }
        }
        .copyable(sortedOrders.filter { selectedOrderIDs.contains($0.id) }.map(\.copyText))
    }

    @ViewBuilder
    func jumpBadge(jumps: Int?) -> some View {
        if let jumps {
            HStack(spacing: 3) {
                Circle()
                    .fill(jumps == 0 ? Color.green : jumps <= 5 ? Color.yellow : Color.orange)
                    .frame(width: 5, height: 5)
                Text(jumps == 0 ? "Here" : "\(jumps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(jumps == 0 ? .green : jumps <= 5 ? .primary : .secondary)
            }
        } else if isComputingJumps {
            ProgressView()
                .controlSize(.mini)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

}
