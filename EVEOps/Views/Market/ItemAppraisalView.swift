import SwiftUI

struct ItemAppraisalView: View {
    @State private var pasteText = ""
    @State private var results: [AppraisalRow] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var unknownNames: [String] = []

    private var totalValue: Double {
        results.reduce(0) { $0 + $1.totalValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: Input
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste Items")
                        .font(.headline)
                    Text("Paste from EVE's show info, cargo scan, or any list.\nFormat: Item Name (tab) Quantity per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    // Summary header
                    if !results.isEmpty {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Total Estimated Value")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(EVEFormatters.formatISK(totalValue))
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(results.count) items resolved")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !unknownNames.isEmpty {
                                    Text("\(unknownNames.count) unresolved")
                                        .font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                        .padding()
                        .background(.regularMaterial)

                        Text("Prices are ESI average market prices. For accurate trading values, check the market browser.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
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
        .navigationTitle("Item Appraisal")
    }

    // MARK:  Row

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
                Text(EVEFormatters.formatISKShort(row.totalValue))
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(row.totalValue > 0 ? .primary : .secondary)
                Text("\(EVEFormatters.formatISKShort(row.unitPrice)) ea")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK:  Appraisal Logic

    private func appraise() async {
        isLoading = true
        error = nil
        results = []
        unknownNames = []

        let parsedItems = parseInput(pasteText)
        guard !parsedItems.isEmpty else {
            error = "No items found. Check your input format."
            isLoading = false
            return
        }

        let allNames = parsedItems.map(\.name)

        // Resolve names → type IDs in batches of 500
        var nameToTypeID: [String: Int] = [:]
        let chunks = stride(from: 0, to: allNames.count, by: 500).map {
            Array(allNames[$0..<min($0 + 500, allNames.count)])
        }
        for chunk in chunks {
            if let response: ESIIDsResponse = try? await ESIClient.shared.post(
                "/universe/ids/",
                body: chunk
            ) {
                let types = response.inventoryTypes ?? []
                for item in types {
                    // Match case-insensitively
                    let lowerName = item.name.lowercased()
                    if let match = chunk.first(where: { $0.lowercased() == lowerName }) {
                        nameToTypeID[match] = item.id
                    }
                }
            }
        }

        // Fetch market prices (all at once, no auth needed)
        let prices: [ESIMarketPrice] = (try? await ESIClient.shared.fetch("/markets/prices/")) ?? []
        let priceByTypeID = Dictionary(uniqueKeysWithValues: prices.map { ($0.typeId, $0) })

        // Build results
        var resolved: [AppraisalRow] = []
        var unresolved: [String] = []

        for item in parsedItems {
            guard let typeID = nameToTypeID[item.name] else {
                unresolved.append(item.name)
                continue
            }
            let priceEntry = priceByTypeID[typeID]
            let unitPrice = priceEntry?.averagePrice ?? priceEntry?.adjustedPrice ?? 0
            resolved.append(AppraisalRow(
                typeID: typeID,
                name: item.name,
                quantity: item.quantity,
                unitPrice: unitPrice,
                totalValue: unitPrice * Double(item.quantity)
            ))
        }

        results = resolved.sorted { $0.totalValue > $1.totalValue }
        unknownNames = unresolved
        isLoading = false
    }

    // MARK:  Parsing

    private func parseInput(_ text: String) -> [(name: String, quantity: Int)] {
        var items: [(name: String, quantity: Int)] = []
        var seen: [String: Int] = [:]  // track index for quantity accumulation

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip common header patterns
            let lower = trimmed.lowercased()
            if lower.hasPrefix("item name") || lower.hasPrefix("name\t") { continue }

            let parts = trimmed.components(separatedBy: "\t")
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            // Try to parse quantity from second column (strip commas, handle "x N" prefix)
            var qty = 1
            if parts.count >= 2 {
                let qtyStr = parts[1].trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: ",", with: "")
                    .replacingOccurrences(of: ".", with: "")
                qty = Int(qtyStr) ?? 1
            }

            // Accumulate duplicate names
            if let idx = seen[name.lowercased()] {
                items[idx] = (name: items[idx].name, quantity: items[idx].quantity + qty)
            } else {
                seen[name.lowercased()] = items.count
                items.append((name: name, quantity: qty))
            }
        }
        return items
    }
}

// MARK:  Data Model

private struct AppraisalRow: Identifiable {
    let typeID: Int
    let name: String
    let quantity: Int
    let unitPrice: Double
    let totalValue: Double
    var id: Int { typeID }
}
