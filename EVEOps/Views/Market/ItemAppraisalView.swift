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
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste Items")
                        .font(.headline)
                    Text("Paste from EVE's show info, cargo scan, or any list.\nFormat: Item Name (tab) Quantity per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text("Market")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Market", selection: $selectedMarket) {
                        ForEach(JaniceMarket.allCases) { market in
                            Text(market.displayName).tag(market)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                TextEditor(text: $pasteText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

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
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle",
                                          description: Text(errorMsg))
                } else if results.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass.circle",
                        description: Text("Paste items on the left and tap Appraise")
                    )
                } else {
                    if !results.isEmpty {
                        // Summary header
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sell Value")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(EVEFormatters.formatISK(totalSell))
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(.green)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Buy Value")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(EVEFormatters.formatISK(totalBuy))
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(.orange)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(results.count) items")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !unknownNames.isEmpty {
                                    Text("\(unknownNames.count) unresolved")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding()
                        .background(.regularMaterial)

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.teal)
                            Text("Live prices via Janice · \(selectedMarket.displayName)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                        Divider()
                    }

                    List {
                        ForEach(results) { row in
                            appraisalRow(row)
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
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Item Appraisal")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("")
    }

    // MARK: Row

    private func appraisalRow(_ row: AppraisalRow) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(row.typeID, size: 64)) { img in
                img.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(.subheadline)
                Text("Qty: \(row.quantity.formatted())")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(EVEFormatters.formatISKShort(row.sellTotal))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(row.sellTotal > 0 ? .green : .secondary)
                Text("\(EVEFormatters.formatISKShort(row.buyTotal)) buy")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.orange.opacity(0.8))
            }
        }
        .padding(.vertical, 2)
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
