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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Galaxy Market Search", systemImage: "globe.europe.africa.fill")
                    .font(.title3.bold())
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape)
            }

            // Item search + order type + search button
            HStack(spacing: 10) {
                if let typeId = selectedTypeId {
                    TypeImage(typeId: typeId, size: 28, cornerRadius: 4)
                }

                HStack(spacing: 6) {
                    if selectedTypeId == nil {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    TextField("Search for an item…", text: $itemSearchText)
                        .textFieldStyle(.plain)
                        .onChange(of: itemSearchText) { _, v in onItemSearchChanged(v) }
                    if isSearchingItems {
                        ProgressView().controlSize(.mini)
                    } else if !itemSearchText.isEmpty {
                        Button { clearItemSelection() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(7)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: 320)

                // Order type picker
                Picker("Order Type", selection: $orderTypeFilter) {
                    Text("Sell").tag(OrderTypeFilter.sell)
                    Text("Buy").tag(OrderTypeFilter.buy)
                    Text("Both").tag(OrderTypeFilter.all)
                }
                .pickerStyle(.segmented)
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

                    HStack(spacing: 6) {
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
                    HStack(spacing: 6) {
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
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
    }

    var orderCountSummary: some View {
        HStack(spacing: 8) {
            if sellCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("\(sellCount) sell")
                }
            }
            if buyCount > 0 {
                HStack(spacing: 4) {
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
                    TypeImage(typeId: result.typeId, size: 48, cornerRadius: 6)
                    Text(result.name).font(.title3)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .listStyle(.plain)
    }

    // MARK:  Searching Progress

    var searchingView: some View {
        VStack(spacing: 16) {
            if totalRegions > 0 {
                ProgressView(value: Double(regionsSearched), total: Double(totalRegions))
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
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Type indicator column — only shown when displaying both order types
                if orderTypeFilter == .all {
                    Text("Type")
                        .frame(width: 40, alignment: .center)
                }
                columnHeader("Price", column: .price, alignment: .trailing)
                    .frame(width: 130)
                columnHeader("Qty", column: .qty, alignment: .trailing)
                    .frame(width: 60)
                    .padding(.leading, 10)
                columnHeader("Station / System", column: .location, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 10)
                columnHeader("Region", column: .region, alignment: .leading)
                    .frame(width: 96)
                    .padding(.leading, 8)
                columnHeader("Sec", column: .sec, alignment: .center)
                    .frame(width: 36)
                if hasLocation {
                    columnHeader("Jumps", column: .jumps, alignment: .center)
                        .frame(width: 60)
                        .padding(.trailing, 4)
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 19)  // 16 base + 3 to align with data rows (which have a 3pt accent bar before their 16pt inner padding)
            .padding(.trailing, 16)
            .padding(.vertical, 6)
            .background(Color(NSColor.separatorColor).opacity(0.15))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedOrders.enumerated()), id: \.element.id) { index, order in
                        orderRow(order, isEven: index % 2 == 0)
                            .contextMenu {
                                let destId = order.order.locationId
                                let name = order.locationName
                                Button {
                                    Task { await setWaypoint(destinationId: destId, clear: true) }
                                } label: {
                                    Label("Set Destination: \(name)", systemImage: "location.fill")
                                }
                                Button {
                                    Task { await setWaypoint(destinationId: destId, clear: false) }
                                } label: {
                                    Label("Add Waypoint: \(name)", systemImage: "plus.circle")
                                }
                            }
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
    }

    func columnHeader(_ title: String, column: SortColumn, alignment: Alignment) -> some View {
        Button { toggleSort(column) } label: {
            HStack(spacing: 3) {
                if alignment == .trailing { Spacer() }
                Text(title)
                    .lineLimit(1)
                    .foregroundStyle(sortColumn == column ? .primary : .secondary)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                if alignment == .leading || alignment == .center { Spacer() }
            }
        }
        .buttonStyle(.plain)
        .help("Sort by \(title)")
    }

    func orderRow(_ resolved: GalaxyOrder, isEven: Bool) -> some View {
        let order = resolved.order
        let sec = resolved.securityStatus
        let accentColor: Color = resolved.isBuyOrder ? .orange : .green

        return HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor.opacity(0.75))
                .frame(width: 3)

            HStack(spacing: 0) {
                // Type badge — only when showing both
                if orderTypeFilter == .all {
                    Text(resolved.isBuyOrder ? "Buy" : "Sell")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(accentColor, in: Capsule())
                        .frame(width: 40, alignment: .center)
                }

                Text(EVEFormatters.formatISK(order.price))
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(accentColor)
                    .frame(width: 130, alignment: .trailing)

                Text(formatCount(order.volumeRemain))
                    .font(.callout.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
                    .padding(.leading, 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolved.locationName)
                        .font(.callout)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(resolved.systemName)
                        if resolved.isBuyOrder {
                            Text("·")
                            Text(formatRange(order.range))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)

                Text(resolved.regionName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 96, alignment: .leading)
                    .padding(.leading, 8)

                Text(String(format: "%.1f", max(0, sec)))
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(securityColor(sec), in: Capsule())
                    .frame(width: 36, alignment: .center)

                if hasLocation {
                    jumpBadge(jumps: resolved.jumps)
                        .frame(width: 52, alignment: .center)
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
        .background(isEven ? Color.primary.opacity(0.03) : Color.clear)
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
                .scaleEffect(0.55)
                .frame(width: 16, height: 16)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

}
