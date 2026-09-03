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

private func skillRoman(_ level: Int) -> String {
    ["I", "II", "III", "IV", "V"][max(0, min(4, level - 1))]
}

// MARK:  Detail Dispatcher

struct CalendarItemDetailView: View {
    let item: CalendarItem

    @ViewBuilder
    var body: some View {
        switch item {
        case .eveEvent(let e):
            CalendarEventDetailPanel(event: e)
        case .skillCompletion(let q, let name):
            SkillDeadlineView(queue: q, skillName: name)
        case .industryJob(let j, let name):
            IndustryJobDeadlineView(job: j, name: name)
        case .piExpiry(let colony, let pins, let sysName):
            PIExpiryDetailView(colony: colony, pins: pins, systemName: sysName)
        case .moonExtract(let m, let name):
            MoonExtractionDetailView(extraction: m, moonName: name)
        case .contractExpiry(let c):
            ContractDeadlineView(contract: c)
        case .marketOrderExpiry(let o, let expiry, let name):
            MarketOrderDeadlineView(order: o, expiry: expiry, typeName: name)
        case .attributeRemap(let d):
            AttributeRemapDetailView(remapDate: d)
        }
    }
}

// MARK:  Shared Detail Header

struct DeadlineHeader: View {
    let title: String
    let source: CalendarItemSource
    let date: Date?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: source.icon)
                        .foregroundStyle(source.color)
                        .font(.title3)
                    Text(title)
                        .font(.headline)
                        .lineLimit(2)
                }
                if let d = date {
                    Text(d, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Label(source.title, systemImage: source.icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(source.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(source.color.opacity(0.12), in: Capsule())
        }
        .padding(16)
        .background(.bar)
    }
}

// MARK:  Skill Deadline

struct SkillDeadlineView: View {
    let queue: ESISkillQueue
    let skillName: String

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(
                title: "\(skillName) \(skillRoman(queue.finishedLevel))",
                source: .skill,
                date: queue.finishDate
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Skill").foregroundStyle(.secondary)
                                Text(skillName)
                            }
                            GridRow {
                                Text("Level").foregroundStyle(.secondary)
                                Text(skillRoman(queue.finishedLevel))
                                    .foregroundStyle(.purple).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Queue Position").foregroundStyle(.secondary)
                                Text("\(queue.queuePosition + 1)")
                            }
                            if let start = queue.startDate {
                                GridRow {
                                    Text("Started").foregroundStyle(.secondary)
                                    Text(start, style: .date)
                                }
                            }
                            if let finish = queue.finishDate {
                                GridRow {
                                    Text("Completes").foregroundStyle(.secondary)
                                    Text(finish, format: .dateTime.month(.abbreviated).day().hour().minute())
                                }
                                GridRow {
                                    Text("Time Left").foregroundStyle(.secondary)
                                    Text(finish, style: .relative)
                                        .foregroundStyle(finish > Date() ? Color.primary : Color.green)
                                }
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Skill Training", systemImage: "brain")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Industry Job Deadline

struct IndustryJobDeadlineView: View {
    let job: ESIIndustryJob
    let name: String?

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(title: name ?? "Industry Job", source: .industryJob, date: job.endDate)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Activity").foregroundStyle(.secondary)
                                Text(activityName(job.activityId))
                                    .foregroundStyle(.orange).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Runs").foregroundStyle(.secondary)
                                Text("\(job.runs)")
                            }
                            GridRow {
                                Text("Status").foregroundStyle(.secondary)
                                Text(job.status.capitalized)
                            }
                            GridRow {
                                Text("Started").foregroundStyle(.secondary)
                                Text(job.startDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Completes").foregroundStyle(.secondary)
                                Text(job.endDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Time Left").foregroundStyle(.secondary)
                                Text(job.endDate, style: .relative)
                                    .foregroundStyle(job.endDate > Date() ? Color.primary : Color.green)
                            }
                            if let cost = job.cost, cost > 0 {
                                GridRow {
                                    Text("Cost").foregroundStyle(.secondary)
                                    Text("\(cost, format: .number.precision(.fractionLength(0))) ISK")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Job Details", systemImage: "hammer")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    private func activityName(_ id: Int) -> String {
        switch id {
        case 1:  return "Manufacturing"
        case 3:  return "TE Research"
        case 4:  return "ME Research"
        case 5:  return "Copying"
        case 7:  return "Reverse Engineering"
        case 8:  return "Invention"
        case 11: return "Reactions"
        default: return "Activity \(id)"
        }
    }
}

// MARK:  PI Expiry Detail

struct PIExpiryDetailView: View {
    let colony: ESIColony
    let pins: [ESIPlanetPin]
    let systemName: String

    private var sortedPins: [ESIPlanetPin] {
        pins.compactMap { $0.expiryTime != nil ? $0 : nil }
            .sorted { ($0.expiryTime ?? .distantFuture) < ($1.expiryTime ?? .distantFuture) }
    }

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(
                title: "\(systemName) · \(colony.planetType.capitalized)",
                source: .piExpiry,
                date: sortedPins.first?.expiryTime
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("System").foregroundStyle(.secondary)
                                Text(systemName)
                            }
                            GridRow {
                                Text("Planet Type").foregroundStyle(.secondary)
                                Text(colony.planetType.capitalized)
                                    .foregroundStyle(.green).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Extractors").foregroundStyle(.secondary)
                                Text("\(sortedPins.count)")
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Colony Info", systemImage: "globe.europe.africa")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sortedPins) { pin in
                                if let expiry = pin.expiryTime {
                                    let num = (sortedPins.firstIndex(where: { $0.pinId == pin.pinId }) ?? 0) + 1
                                    HStack {
                                        Image(systemName: "circle.fill")
                                            .font(.system(size: 6))
                                            .foregroundStyle(.green.opacity(0.8))
                                        Text("Extractor \(num)").font(.subheadline)
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 1) {
                                            Text(expiry, style: .relative)
                                                .font(.caption)
                                                .foregroundStyle(expiry > Date() ? Color.secondary : Color.red)
                                            Text(expiry, format: .dateTime.month(.abbreviated).day().hour().minute())
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    if pin.pinId != sortedPins.last?.pinId { Divider() }
                                }
                            }
                        }
                    } label: {
                        Label("Extractor Expiry", systemImage: "arrow.down.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Moon Extraction Detail

struct MoonExtractionDetailView: View {
    let extraction: ESIMoonExtraction
    let moonName: String?

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(
                title: moonName ?? "Moon Chunk Ready",
                source: .moonExtract,
                date: extraction.chunkArrivalTime
            )
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Moon").foregroundStyle(.secondary)
                                Text(moonName ?? "#\(extraction.moonId)")
                            }
                            GridRow {
                                Text("Extraction Start").foregroundStyle(.secondary)
                                Text(extraction.extractionStartTime,
                                     format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Chunk Arrives").foregroundStyle(.secondary)
                                Text(extraction.chunkArrivalTime,
                                     format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Time Until Pop").foregroundStyle(.secondary)
                                Text(extraction.chunkArrivalTime, style: .relative)
                                    .foregroundStyle(extraction.chunkArrivalTime > Date()
                                        ? .primary
                                        : Color(hue: 0.12, saturation: 0.85, brightness: 0.95))
                            }
                            GridRow {
                                Text("Auto-fires").foregroundStyle(.secondary)
                                Text(extraction.naturalDecayTime,
                                     format: .dateTime.month(.abbreviated).day().hour().minute())
                            }
                            GridRow {
                                Text("Decay In").foregroundStyle(.secondary)
                                Text(extraction.naturalDecayTime, style: .relative)
                                    .foregroundStyle(.red)
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Extraction Details", systemImage: "moon.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Contract Deadline

struct ContractDeadlineView: View {
    let contract: ESIContract

    var body: some View {
        let heading = contract.title.flatMap { $0.isEmpty ? nil : $0 } ?? contractTypeName(contract.type)
        VStack(spacing: 0) {
            DeadlineHeader(title: heading, source: .contractExpiry, date: contract.dateExpired)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Type").foregroundStyle(.secondary)
                                Text(contractTypeName(contract.type))
                                    .foregroundStyle(.red).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Availability").foregroundStyle(.secondary)
                                Text(contract.availability.capitalized)
                            }
                            GridRow {
                                Text("Issued").foregroundStyle(.secondary)
                                Text(contract.dateIssued, format: .dateTime.month(.abbreviated).day().year())
                            }
                            GridRow {
                                Text("Expires").foregroundStyle(.secondary)
                                Text(contract.dateExpired, format: .dateTime.month(.abbreviated).day().year())
                            }
                            GridRow {
                                Text("Time Left").foregroundStyle(.secondary)
                                Text(contract.dateExpired, style: .relative)
                                    .foregroundStyle(contract.dateExpired > Date() ? Color.primary : Color.red)
                            }
                            if let price = contract.price, price > 0 {
                                GridRow {
                                    Text("Price").foregroundStyle(.secondary)
                                    Text("\(price, format: .number.precision(.fractionLength(0))) ISK")
                                }
                            }
                            if let reward = contract.reward, reward > 0 {
                                GridRow {
                                    Text("Reward").foregroundStyle(.secondary)
                                    Text("\(reward, format: .number.precision(.fractionLength(0))) ISK")
                                }
                            }
                            if let collateral = contract.collateral, collateral > 0 {
                                GridRow {
                                    Text("Collateral").foregroundStyle(.secondary)
                                    Text("\(collateral, format: .number.precision(.fractionLength(0))) ISK")
                                }
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Contract Details", systemImage: "doc.text")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }

    private func contractTypeName(_ type: String) -> String {
        switch type {
        case "item_exchange": return "Item Exchange"
        case "auction":       return "Auction"
        case "courier":       return "Courier"
        case "loan":          return "Loan"
        default:              return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK:  Market Order Deadline

struct MarketOrderDeadlineView: View {
    let order: ESIMarketOrder
    let expiry: Date
    let typeName: String?

    var body: some View {
        let isBuy   = order.isBuyOrder == true
        let dir     = isBuy ? "Buy" : "Sell"
        let heading = typeName.map { "\($0) \(dir) Order" } ?? "\(dir) Order"
        VStack(spacing: 0) {
            DeadlineHeader(title: heading, source: .marketOrder, date: expiry)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Item").foregroundStyle(.secondary)
                                Text(typeName ?? "#\(order.typeId)")
                            }
                            GridRow {
                                Text("Type").foregroundStyle(.secondary)
                                Text(isBuy ? "Buy Order" : "Sell Order")
                                    .foregroundStyle(.cyan).fontWeight(.semibold)
                            }
                            GridRow {
                                Text("Price").foregroundStyle(.secondary)
                                Text("\(order.price, format: .number.precision(.fractionLength(2))) ISK")
                            }
                            GridRow {
                                Text("Volume").foregroundStyle(.secondary)
                                Text("\(order.volumeRemain) / \(order.volumeTotal)")
                            }
                            GridRow {
                                Text("Range").foregroundStyle(.secondary)
                                Text(order.range.replacingOccurrences(of: "_", with: " ").capitalized)
                            }
                            GridRow {
                                Text("Duration").foregroundStyle(.secondary)
                                Text("\(order.duration) days")
                            }
                            GridRow {
                                Text("Expires").foregroundStyle(.secondary)
                                Text(expiry, format: .dateTime.month(.abbreviated).day().year())
                            }
                            GridRow {
                                Text("Time Left").foregroundStyle(.secondary)
                                Text(expiry, style: .relative)
                                    .foregroundStyle(expiry > Date() ? Color.primary : Color.red)
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Order Details", systemImage: "cart")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}

// MARK:  Attribute Remap Detail

struct AttributeRemapDetailView: View {
    let remapDate: Date

    var body: some View {
        VStack(spacing: 0) {
            DeadlineHeader(title: "Attribute Remap Available", source: .attributeRemap, date: remapDate)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow {
                                Text("Available On").foregroundStyle(.secondary)
                                Text(remapDate, format: .dateTime.month(.wide).day().year())
                            }
                            GridRow {
                                Text("Time Until").foregroundStyle(.secondary)
                                Text(remapDate, style: .relative)
                                    .foregroundStyle(remapDate > Date() ? Color.primary : Color.pink)
                            }
                        }
                        .font(.subheadline)
                    } label: {
                        Label("Remap Cooldown", systemImage: "slider.horizontal.3")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }

                    GroupBox {
                        Text("When the cooldown expires you can reassign your base attributes (Charisma, Intelligence, Memory, Perception, Willpower) to optimise training time for a new skill plan.")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("About Remaps", systemImage: "info.circle")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
        }
    }
}
