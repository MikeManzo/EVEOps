//
// EFTSerializer.swift
// EVEOps
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
import SwiftUI
import UniformTypeIdentifiers

// MARK: UTType

extension UTType {
    static let eveFitting = UTType("com.eveops.eft-fitting") ?? .plainText
}

// MARK: EFTFittingDocument

struct EFTFittingDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.eveFitting, .plainText] }
    var text: String

    init(text: String = "") { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

// MARK: EFTTransferable

struct EFTTransferable: Transferable {
    let text: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .eveFitting) { item in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(item.filename)
            try item.text.write(to: url, atomically: true, encoding: .utf8)
            if let iconURL = Bundle.main.url(forResource: "EFTDocument", withExtension: "icns"),
               let icon = NSImage(contentsOf: iconURL) {
                NSWorkspace.shared.setIcon(icon, forFile: url.path, options: [])
            }
            return SentTransferredFile(url)
        } importing: { received in
            EFTTransferable(
                text: (try? String(contentsOf: received.file, encoding: .utf8)) ?? "",
                filename: received.file.lastPathComponent
            )
        }
    }
}

// MARK: EFTSerializer

enum EFTSerializer {

    struct ParsedFitting {
        let shipTypeName: String
        let fittingName: String
        // Sections in slot order: HiSlot, MedSlot, LoSlot, RigSlot, SubSystem
        let sections: [(prefix: String, names: [String])]
        // Drones, fighters, and cargo items with optional quantities
        let extras: [(name: String, qty: Int)]
    }

    struct ParseError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Export — Saved Fitting

    static func export(fitting: SavedFittingEntry, typeNames: [Int: String]) -> String {
        eftText(name: fitting.name, shipTypeName: fitting.shipTypeName,
                items: fitting.items, typeNames: typeNames)
    }

    // MARK: Export — Simulator

    static func exportSimulator(
        shipTypeName: String,
        fittingName: String,
        slots: [SimSlot],
        moduleTypes: [Int: ESIType]
    ) -> String {
        var lines: [String] = ["[\(shipTypeName), \(fittingName)]"]
        let order: [SimSlotCategory] = [.high, .medium, .low, .rig, .subsystem]
        for (i, category) in order.enumerated() {
            if i > 0 { lines.append("") }
            for slot in slots.filter({ $0.category == category }).sorted(by: { $0.index < $1.index }) {
                if let typeId = slot.moduleTypeId, let name = moduleTypes[typeId]?.name {
                    lines.append(name)
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Parse

    static func parse(eftText text: String) throws -> ParsedFitting {
        // Normalize line endings and strip BOM
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let cleaned = normalized.hasPrefix("\u{FEFF}") ? String(normalized.dropFirst()) : normalized

        var lines = cleaned.components(separatedBy: "\n")
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }

        guard let headerLine = lines.first else { throw ParseError(message: "Empty file") }
        let header = headerLine.trimmingCharacters(in: .whitespaces)
        guard header.hasPrefix("["), header.hasSuffix("]") else {
            throw ParseError(message: "Expected header line in format [Ship Type, Fitting Name]")
        }

        let inner = String(header.dropFirst().dropLast())
        let parts = inner.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw ParseError(message: "Header must be [Ship Type, Fitting Name] with both fields non-empty")
        }

        // Rejoin and split body by double newlines to get sections.
        // Empty blocks are preserved so section indices stay aligned with slot types.
        let body = lines.dropFirst().joined(separator: "\n")
        let rawBlocks = body.components(separatedBy: "\n\n")
        let slotPrefixes = ["HiSlot", "MedSlot", "LoSlot", "RigSlot", "SubSystem"]

        var sections: [(prefix: String, names: [String])] = []
        var extras: [(name: String, qty: Int)] = []

        for (i, rawBlock) in rawBlocks.enumerated() {
            let names = rawBlock
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("[Empty") }
            if i < slotPrefixes.count {
                sections.append((prefix: slotPrefixes[i], names: names))
            } else {
                extras.append(contentsOf: names.map { parseQtyLine($0) })
            }
        }

        return ParsedFitting(shipTypeName: parts[0], fittingName: parts[1],
                             sections: sections, extras: extras)
    }

    // MARK: Resolve names → type IDs

    static func resolve(
        parsed: ParsedFitting,
        account: StoredAccount,
        token: String
    ) async throws -> (shipTypeId: Int, name: String, items: [ESIFittingItem]) {
        var allNames = Set([parsed.shipTypeName])
        parsed.sections.forEach { $0.names.forEach { allNames.insert($0) } }
        parsed.extras.forEach { allNames.insert($0.name) }

        var nameToId: [String: Int] = [:]
        struct SearchResp: Decodable { let inventoryType: [Int]? }

        await withTaskGroup(of: (String, Int?).self) { group in
            for name in allNames {
                group.addTask {
                    let resp: SearchResp? = try? await ESIClient.shared.fetch(
                        "/characters/\(account.characterID)/search/",
                        token: token,
                        queryItems: [
                            URLQueryItem(name: "categories", value: "inventory_type"),
                            URLQueryItem(name: "search", value: name),
                            URLQueryItem(name: "strict", value: "true")
                        ]
                    )
                    return (name, resp?.inventoryType?.first)
                }
            }
            for await (name, id) in group {
                if let id { nameToId[name] = id }
            }
        }

        guard let shipTypeId = nameToId[parsed.shipTypeName] else {
            throw ParseError(message: "Ship type '\(parsed.shipTypeName)' not found in EVE database")
        }

        var items: [ESIFittingItem] = []
        for section in parsed.sections {
            for (idx, name) in section.names.enumerated() {
                guard let typeId = nameToId[name] else { continue }
                items.append(ESIFittingItem(flag: "\(section.prefix)\(idx)", quantity: 1, typeId: typeId))
            }
        }
        for (name, qty) in parsed.extras {
            guard let typeId = nameToId[name] else { continue }
            items.append(ESIFittingItem(flag: "DroneBay", quantity: qty, typeId: typeId))
        }

        return (shipTypeId, parsed.fittingName, items)
    }

    // MARK: Private Helpers

    private static func eftText(
        name: String,
        shipTypeName: String,
        items: [ESIFittingItem],
        typeNames: [Int: String]
    ) -> String {
        var lines: [String] = ["[\(shipTypeName), \(name)]"]
        let prefixes = ["HiSlot", "MedSlot", "LoSlot", "RigSlot", "SubSystem"]
        for (i, prefix) in prefixes.enumerated() {
            if i > 0 { lines.append("") }
            for item in items
                .filter({ $0.flag.hasPrefix(prefix) })
                .sorted(by: { slotIndex($0.flag, prefix: prefix) < slotIndex($1.flag, prefix: prefix) }) {
                lines.append(typeNames[item.typeId] ?? "Unknown Module")
            }
        }
        let extras = items.filter { $0.flag == "DroneBay" || $0.flag == "FighterBay" || $0.flag == "Cargo" }
        if !extras.isEmpty {
            lines.append("")
            for item in extras {
                let n = typeNames[item.typeId] ?? "Unknown"
                lines.append(item.quantity > 1 ? "\(n) x\(item.quantity)" : n)
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func slotIndex(_ flag: String, prefix: String) -> Int {
        Int(flag.dropFirst(prefix.count)) ?? 0
    }

    private static func parseQtyLine(_ line: String) -> (name: String, qty: Int) {
        // Parse "Hornet I x5" → ("Hornet I", 5); plain names return qty 1
        let parts = line.components(separatedBy: " x")
        if parts.count >= 2, let qty = Int(parts.last!) {
            return (parts.dropLast().joined(separator: " x"), qty)
        }
        return (line, 1)
    }
}
