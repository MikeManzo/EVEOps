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

struct ItemAppraisalView: View {
    @State private var pasteText = ""
    @State private var results: [AppraisalRow] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var unknownNames: [String] = []
    @State private var selectedMarket: JaniceMarket = .jita

    private var totalSell: Double { results.reduce(0) { $0 + $1.sellTotal } }
    private var totalBuy:  Double { results.reduce(0) { $0 + $1.buyTotal  } }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Input panel
            VStack(alignment: .leading, spacing: EVESpacing.lg) {
                VStack(alignment: .leading, spacing: EVESpacing.xs) {
                    Text("Paste Items")
                        .font(.headline)
                    Text("Paste from EVE's show info, cargo scan, or any list.\nFormat: Item Name (tab) Quantity per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: EVESpacing.sm) {
                    Text("Market")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    EVEMenuPicker("Market", selection: $selectedMarket,
                                  options: JaniceMarket.allCases.map { EVEMenuOption($0, verbatim: $0.displayName) })
                }

                TextEditor(text: $pasteText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: EVERadius.md))

                HStack {
                    Button("Clear") {
                        pasteText = ""
                        results = []
                        error = nil
                        unknownNames = []
                    }
                    .disabled(pasteText.isEmpty)

                    Spacer()

                    if isLoading {
                        ProgressView().controlSize(.small)
                    }

                    Button("Appraise") {
                        Task { await appraise() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                }
            }
            .padding()
            .frame(width: 300)

            Divider()

            // Right: Results
            VStack(spacing: 0) {
                if let errorMsg = error {
                    EVEEmptyState("Error", systemImage: "exclamationmark.triangle", message: Text(errorMsg), tint: .orange)
                } else if results.isEmpty && !isLoading {
                    EVEEmptyState("No Results", systemImage: "magnifyingglass.circle", message: Text("Paste items on the left and tap Appraise"))
                } else {
                    if !results.isEmpty {
                        // Summary header
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                                Text("Sell Value")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(EVEFormatters.formatISK(totalSell))
                                    .font(.eveStat)
                                    .foregroundStyle(.green)
                                    .eveNumeric(totalSell)
                            }
                            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                                Text("Buy Value")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(EVEFormatters.formatISK(totalBuy))
                                    .font(.eveStat)
                                    .foregroundStyle(.orange)
                                    .eveNumeric(totalBuy)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: EVESpacing.xxs) {
                                Text("\(results.count) items")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !unknownNames.isEmpty {
                                    Text("\(unknownNames.count) unresolved")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding()
                        .background(EVESurface.bar)

                        HStack(spacing: EVESpacing.xs) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                            Text("Live prices via Janice · \(selectedMarket.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, EVESpacing.xs)

                        Divider()
                    }

                    List {
                        ForEach(results) { row in
                            appraisalRow(row)
                                .contentShape(Rectangle())
                                .eveContextMenu(.item(typeID: row.typeID, name: row.name))
                        }
                        if !unknownNames.isEmpty {
                            Section("Unresolved (\(unknownNames.count))") {
                                ForEach(unknownNames, id: \.self) { name in
                                    Label(name, systemImage: "questionmark.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .eveScreenHeader("Item Appraisal")
    }

    // MARK: Row

    private func appraisalRow(_ row: AppraisalRow) -> some View {
        HStack(spacing: 10) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(row.typeID, size: 64)) { img in
                img.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))

            VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                Text(row.name).font(.subheadline)
                Text("Qty: \(row.quantity.formatted())")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: EVESpacing.xxs) {
                Text(EVEFormatters.formatISKShort(row.sellTotal))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(row.sellTotal > 0 ? .green : .secondary)
                Text("\(EVEFormatters.formatISKShort(row.buyTotal)) buy")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .padding(.vertical, EVESpacing.xxs)
    }

    // MARK: Appraise

    private func appraise() async {
        isLoading = true
        error = nil
        results = []
        unknownNames = []

        let trimmed = pasteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "No items found. Check your input format."
            isLoading = false
            return
        }

        do {
            let appraisal = try await JaniceClient.shared.appraise(trimmed, market: selectedMarket)
            results = appraisal.items
                .sorted { $0.sellTotal > $1.sellTotal }
                .map { item in
                    AppraisalRow(
                        typeID:      item.typeId,
                        name:        item.name,
                        quantity:    item.amount,
                        buyPerUnit:  item.buyPerUnit,
                        sellPerUnit: item.sellPerUnit
                    )
                }
            unknownNames = appraisal.unknownItems
            if results.isEmpty && unknownNames.isEmpty {
                error = "Janice could not resolve any items. Check your input format."
            }
        } catch {
            self.error = "Appraisal failed: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: Data Model

private struct AppraisalRow: Identifiable {
    let typeID: Int
    let name: String
    let quantity: Int
    let buyPerUnit: Double
    let sellPerUnit: Double
    var id: Int { typeID }
    var buyTotal:  Double { buyPerUnit  * Double(quantity) }
    var sellTotal: Double { sellPerUnit * Double(quantity) }
}
