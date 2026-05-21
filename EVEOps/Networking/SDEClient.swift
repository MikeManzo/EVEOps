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
import Darwin // for dlopen / dlsym / dlclose

// MARK: - Model

/// A groupId patch extracted from the EVE SDE for a single LocationGroupModifier record.
struct LGMPatch: Codable, Sendable {
    let modifiedAttrId:  Int?
    let modifyingAttrId: Int?
    let operatorId:      Int?
    let groupId:         Int
    let domain:          String?
}

// MARK: - Client

/// Downloads and caches the `dgmEffectsModifierInfo` table from the Fuzzwork SDE MySQL dump,
/// extracting only `LocationGroupModifier` records so that `UniverseCache` can fill in
/// the `groupId` values that ESI leaves nil for every LGM modifier.
///
/// Disk cache lives at `Caches/EVEOps/sde/` with a 7-day TTL.
actor SDEClient {
    static let shared = SDEClient()

    // patches[effectId] = all LGM patches for that effect
    private var patches: [Int: [LGMPatch]] = [:]
    // typeEffects[typeId] = all effectIds the SDE assigns to that type (superset of ESI's list)
    private var typeEffects: [Int: [Int]] = [:]
    private var loaded  = false

    private static let ttl: TimeInterval = 7 * 24 * 3600

    // Fuzzwork hosts SDE dumps in versioned dirs: /dump/experimental-{build}_{date}/
    // We discover the latest by scraping their index page.
    private static let fuzzworkIndexURL = URL(string: "https://www.fuzzwork.co.uk/dump/")!

    // URLSession with extended timeout for the 79 MB download.
    private static let downloadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = 120   // 2 min per read
        cfg.timeoutIntervalForResource = 600   // 10 min total
        return URLSession(configuration: cfg)
    }()

    private static let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps/sde", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static var dataURL: URL { cacheDir.appendingPathComponent("lgmPatches.json") }
    private static var metaURL: URL { cacheDir.appendingPathComponent("lgmPatches.meta.json") }

    private init() {}

    // MARK: Public API

    /// Ensures SDE data is loaded; safe to call from any actor.
    func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true   // set first to prevent concurrent re-entry
        await load()
    }

    /// Returns the full LGM-patch map after `ensureLoaded()` has been awaited.
    func allPatches() -> [Int: [LGMPatch]] { patches }

    // MARK: Load

    private func load() async {
        if let saved = loadFromDisk(), !saved.isEmpty {
            patches = saved
            print("[SDEClient] Loaded \(saved.values.map(\.count).reduce(0,+)) LGM patches from disk cache")
            return
        }
        await download()
    }

    private func download() async {
        guard let fileURL = await discoverFuzzworkURL() else {
            print("[SDEClient] Could not discover Fuzzwork SDE URL — groupId patching disabled")
            return
        }

        print("[SDEClient] Downloading SDE (\(fileURL.lastPathComponent))…")
        guard let (data, resp) = try? await Self.downloadSession.data(from: fileURL),
              let http = resp as? HTTPURLResponse, http.statusCode == 200
        else {
            print("[SDEClient] Download failed")
            return
        }
        print("[SDEClient] Downloaded \(data.count / 1_048_576) MB")

        // Detect gzip by magic bytes (1F 8B) and decompress.
        // The Fuzzwork sdeyaml_mysql_*.sql.gz is double-gzipped (outer gzip wraps inner gzip).
        var rawData: Data
        if data.count >= 2, data[0] == 0x1F, data[1] == 0x8B {
            print("[SDEClient] Decompressing gzip…")
            guard var decompressed = decompressGzip(data) else {
                print("[SDEClient] Gzip decompression failed")
                return
            }
            // Handle double-gzipped files: outer layer decompresses to another gzip.
            if decompressed.count >= 2, decompressed[0] == 0x1F, decompressed[1] == 0x8B {
                print("[SDEClient] Detected double-gzip, decompressing inner layer…")
                guard let inner = decompressGzip(decompressed) else {
                    print("[SDEClient] Inner gzip decompression failed")
                    return
                }
                decompressed = inner
            }
            rawData = decompressed
            print("[SDEClient] Decompressed to \(rawData.count / 1_048_576) MB")
        } else {
            rawData = data
        }

        // Extract just the dgmEffectsModifierInfo section, then parse SQL.
        guard let section = extractSDESection(rawData) else {
            print("[SDEClient] dgmEffectsModifierInfo not found in dump")
            return
        }

        let p = parseSQL(section)
        if !p.isEmpty {
            patches = p
            saveToDisk(p)
        } else {
            print("[SDEClient] SQL parse returned no LGM patches")
        }
    }

    // MARK: Discovery

    /// Scrapes the Fuzzwork dump index to find the latest `experimental-*` directory,
    /// then scans that directory listing for `sdeyaml_mysql_*.sql.gz`.
    private func discoverFuzzworkURL() async -> URL? {
        print("[SDEClient] Fetching Fuzzwork index…")
        guard let (idxData, idxResp) = try? await URLSession.shared.data(from: Self.fuzzworkIndexURL),
              let idxHttp = idxResp as? HTTPURLResponse, idxHttp.statusCode == 200,
              let idxHtml = String(data: idxData, encoding: .utf8)
        else {
            print("[SDEClient] Fuzzwork index fetch failed")
            return nil
        }

        // Match: experimental-3351823_20260519/  or  experimental-20260511/
        guard let re = try? NSRegularExpression(pattern: #"href="(experimental-(\d+_)?(\d{8})/)"#)
        else { return nil }

        struct Entry: Comparable {
            let dir: String; let date: String; let build: Int
            static func < (a: Entry, b: Entry) -> Bool {
                a.date == b.date ? a.build < b.build : a.date < b.date
            }
        }
        let ns = idxHtml as NSString
        let entries: [Entry] = re.matches(in: idxHtml, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                guard m.range(at: 1).location != NSNotFound,
                      m.range(at: 3).location != NSNotFound
                else { return nil }
                let dir   = String(ns.substring(with: m.range(at: 1)).dropLast())
                let build = m.range(at: 2).location != NSNotFound
                    ? (Int(ns.substring(with: m.range(at: 2)).dropLast()) ?? 0) : 0
                let date  = ns.substring(with: m.range(at: 3))
                return Entry(dir: dir, date: date, build: build)
            }

        guard let latest = entries.max() else {
            print("[SDEClient] No experimental-* directories found in Fuzzwork index")
            return nil
        }

        let base = "https://www.fuzzwork.co.uk/dump/\(latest.dir)/"
        print("[SDEClient] Latest SDE dir: \(latest.dir)")

        guard let (dirData, dirResp) = try? await URLSession.shared.data(from: URL(string: base)!),
              let dirHttp = dirResp as? HTTPURLResponse, dirHttp.statusCode == 200,
              let dirHtml = String(data: dirData, encoding: .utf8)
        else {
            print("[SDEClient] Directory listing fetch failed")
            return nil
        }

        // Find sdeyaml_mysql_*.sql.gz (the full SDE MySQL dump)
        if let fileRe = try? NSRegularExpression(pattern: #"href="(sdeyaml_mysql_[^"]+\.sql\.gz)""#) {
            let ns2 = dirHtml as NSString
            if let m = fileRe.firstMatch(in: dirHtml, range: NSRange(location: 0, length: ns2.length)),
               m.range(at: 1).location != NSNotFound {
                let filename = ns2.substring(with: m.range(at: 1))
                let url = URL(string: base + filename)!
                print("[SDEClient] Found MySQL dump: \(filename)")
                return url
            }
        }

        print("[SDEClient] sdeyaml_mysql_*.sql.gz not found in directory listing")
        return nil
    }

    // MARK: Gzip decompression (via system libz)

    /// Decompresses a gzip payload using `inflate` from `/usr/lib/libz.dylib` via dlopen.
    /// Uses `inflateInit2_` with windowBits=47 which auto-detects gzip vs zlib headers.
    private func decompressGzip(_ compressed: Data) -> Data? {
        guard compressed.count >= 2, compressed[0] == 0x1F, compressed[1] == 0x8B else { return nil }

        guard let libz       = dlopen("/usr/lib/libz.dylib", RTLD_LAZY),
              let initSym    = dlsym(libz, "inflateInit2_"),
              let inflateSym = dlsym(libz, "inflate"),
              let endSym     = dlsym(libz, "inflateEnd"),
              let verSym     = dlsym(libz, "zlibVersion")
        else { return nil }
        defer { dlclose(libz) }

        typealias Init2Fn   = @convention(c) (UnsafeMutableRawPointer, Int32, UnsafePointer<CChar>, Int32) -> Int32
        typealias InflateFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Int32
        typealias EndFn     = @convention(c) (UnsafeMutableRawPointer) -> Int32
        typealias VerFn     = @convention(c) () -> UnsafePointer<CChar>

        let inflateInit2_ = unsafeBitCast(initSym,    to: Init2Fn.self)
        let inflate_      = unsafeBitCast(inflateSym, to: InflateFn.self)
        let inflateEnd_   = unsafeBitCast(endSym,     to: EndFn.self)
        let zlibVersion_  = unsafeBitCast(verSym,     to: VerFn.self)

        // z_stream layout on macOS 64-bit (112 bytes total):
        //   offset  0: next_in  (pointer, 8 bytes)
        //   offset  8: avail_in (UInt32,  4 bytes)
        //   offset 24: next_out (pointer, 8 bytes)
        //   offset 32: avail_out(UInt32,  4 bytes)
        let strm = UnsafeMutableRawPointer.allocate(byteCount: 112, alignment: 8)
        defer { strm.deallocate() }
        strm.initializeMemory(as: UInt8.self, repeating: 0, count: 112)

        // windowBits = 47 → MAX_WBITS(15) + 32 = auto-detect gzip or zlib header
        let initRC = inflateInit2_(strm, 47, zlibVersion_(), 112)
        guard initRC == 0 else {
            print("[SDEClient] inflateInit2_ failed rc=\(initRC)")
            return nil
        }
        defer { _ = inflateEnd_(strm) }

        var output = Data()
        output.reserveCapacity(compressed.count * 5)
        let chunkSize = 1 << 20  // 1 MB output chunks
        var chunk = [UInt8](repeating: 0, count: chunkSize)

        return compressed.withUnsafeBytes { src in
            strm.storeBytes(of: src.baseAddress!, toByteOffset: 0, as: UnsafeRawPointer.self)
            strm.storeBytes(of: UInt32(compressed.count), toByteOffset: 8, as: UInt32.self)

            var status: Int32 = 0
            repeat {
                // inflate_ MUST be called inside withUnsafeMutableBytes so the next_out
                // pointer remains pinned for the entire duration of the zlib call.
                status = chunk.withUnsafeMutableBytes { dst -> Int32 in
                    strm.storeBytes(of: dst.baseAddress!, toByteOffset: 24, as: UnsafeMutableRawPointer.self)
                    strm.storeBytes(of: UInt32(chunkSize), toByteOffset: 32, as: UInt32.self)
                    return inflate_(strm, 0)  // Z_NO_FLUSH = 0
                }
                if status < 0, status != -5 {
                    print("[SDEClient] inflate error rc=\(status)")
                    return nil
                }
                let avail_out = strm.load(fromByteOffset: 32, as: UInt32.self)
                let have = chunkSize - Int(avail_out)
                if have > 0 { output.append(contentsOf: chunk.prefix(have)) }
                // Z_BUF_ERROR with no output and no input remaining = stalled / truncated data.
                if status == -5, have == 0 {
                    let avail_in = strm.load(fromByteOffset: 8, as: UInt32.self)
                    if avail_in == 0 {
                        print("[SDEClient] inflate stalled — data may be truncated")
                        return nil
                    }
                }
            } while status != 1  // until Z_STREAM_END

            print("[SDEClient] Decompressed: \(output.count / 1_048_576) MB")
            return output
        }
    }

    // MARK: Section extraction

    /// Searches the decompressed SQL dump for the modifier info table and
    /// returns just the INSERT INTO block as a String.
    /// Tries candidate table names in order and falls back to listing available dgm* tables.
    private func extractSDESection(_ data: Data) -> String? {
        // Candidates in preference order.
        // dgmEffects (YAML SDE): modifierInfo stored as a JSON column in the main effects table.
        // dgmEffectModifiers / dgmEffectsModifierInfo: separate table in older SDE formats.
        let candidates = ["dgmEffects", "dgmEffectModifiers", "dgmEffectsModifierInfo"]

        for tableName in candidates {
            guard let insertKey = "INSERT INTO `\(tableName)`".data(using: .utf8) else { continue }
            guard let insertRange = data.range(of: insertKey) else { continue }

            let semiData = Data([0x3B])
            let afterInsert = insertRange.upperBound..<data.endIndex
            guard let semiRange = data.range(of: semiData, options: [], in: afterInsert) else {
                print("[SDEClient] Closing semicolon not found after INSERT for \(tableName)")
                continue
            }

            let createKey = "CREATE TABLE `\(tableName)`".data(using: .utf8)!
            let startPos: Data.Index
            if let createRange = data.range(of: createKey) {
                startPos = createRange.lowerBound
            } else {
                startPos = insertRange.lowerBound
            }

            let section = data[startPos..<semiRange.upperBound]
            print("[SDEClient] Extracted \(tableName) section: \(section.count / 1024) KB")
            if let preview = String(data: section.prefix(200), encoding: .utf8) {
                print("[SDEClient] Section preview: \(preview.prefix(200))")
            }
            return String(data: section, encoding: .utf8)
        }

        // Neither candidate found — list ALL table names to determine the actual schema.
        print("[SDEClient] Neither candidate table found. Scanning all CREATE TABLE names…")
        let createPrefix = "CREATE TABLE `".data(using: .utf8)!
        var searchFrom = data.startIndex
        var allTables: [String] = []
        while allTables.count < 60 {
            guard let r = data.range(of: createPrefix, options: [], in: searchFrom..<data.endIndex) else { break }
            // r.upperBound is right after the opening backtick — read until closing backtick.
            let nameStart = r.upperBound
            let nameEnd   = min(nameStart + 80, data.endIndex)
            if let chunk = String(data: data[nameStart..<nameEnd], encoding: .utf8) {
                allTables.append(chunk.prefix(while: { $0 != "`" }).description)
            }
            searchFrom = r.upperBound
        }
        let dgmTables = allTables.filter { $0.lowercased().contains("dgm") || $0.lowercased().contains("modifier") || $0.lowercased().contains("effect") }
        print("[SDEClient] All tables (\(allTables.count)): \(allTables.prefix(30))")
        print("[SDEClient] dgm/modifier/effect tables: \(dgmTables)")
        return nil
    }

    // MARK: SQL parsing (MySQL INSERT format)

    /// Entry point: dispatches to the appropriate parser based on which table was extracted.
    private func parseSQL(_ section: String) -> [Int: [LGMPatch]] {
        if section.contains("INSERT INTO `dgmEffects`") {
            return parseDgmEffectsJSON(section)
        }
        return parseLegacySeparateTable(section)
    }

    /// YAML SDE format: `dgmEffects` stores modifier info as a JSON array in a `modifierInfo` column.
    /// Finds every `LocationGroupModifier` JSON object in the section and extracts its effectID by
    /// searching backward for the VALUES row start pattern `(INTEGER,`.
    private func parseDgmEffectsJSON(_ section: String) -> [Int: [LGMPatch]] {
        // Diagnostics: show full CREATE TABLE + first INSERT row so we know the actual schema.
        if let ctRange = section.range(of: "CREATE TABLE") {
            print("[SDEClient] dgmEffects schema:\n\(section[ctRange.lowerBound...].prefix(2000))")
        }
        // Show actual content around the first LocationGroupModifier occurrence.
        if let lgmRange = section.range(of: "LocationGroupModifier") {
            let start = section.index(lgmRange.lowerBound, offsetBy: -300, limitedBy: section.startIndex) ?? section.startIndex
            let end   = section.index(lgmRange.upperBound, offsetBy: 300, limitedBy: section.endIndex)   ?? section.endIndex
            print("[SDEClient] LGM context (600 chars around first hit):\n'\(section[start..<end])'")
        } else {
            print("[SDEClient] 'LocationGroupModifier' not found in section")
        }
        // MySQL stores JSON strings with backslash-escaped quotes: \"key\": \"value\"
        // Match objects containing \"LocationGroupModifier\" — no nested {} possible in these flat records.
        guard let objRe = try? NSRegularExpression(
            pattern: #"\{[^}]*\\"LocationGroupModifier\\"[^}]*\}"#
        ) else { return [:] }

        // Match start of a VALUES row: (INTEGER,  — parens don't appear inside JSON.
        guard let rowStartRe = try? NSRegularExpression(pattern: #"\((\d+),"#) else { return [:] }

        var result: [Int: [LGMPatch]] = [:]
        let ns = section as NSString
        let length = ns.length

        objRe.enumerateMatches(in: section, range: NSRange(location: 0, length: length)) { match, _, _ in
            guard let match else { return }
            // Unescape MySQL's backslash-quoted strings (\") to get valid JSON ("").
            let unescaped = ns.substring(with: match.range)
                             .replacingOccurrences(of: "\\\"", with: "\"")

            guard let objData = unescaped.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: objData) as? [String: Any],
                  let groupId = obj["groupID"] as? Int else { return }

            let modifiedAttrId  = obj["modifiedAttributeID"]  as? Int
            let modifyingAttrId = obj["modifyingAttributeID"] as? Int
            let operation       = obj["operation"]             as? Int
            let domain          = obj["domain"]                as? String

            // Search the 20 KB before this JSON object for the last `(INTEGER,` row start.
            let windowStart = max(0, match.range.location - 20_000)
            let window   = ns.substring(with: NSRange(location: windowStart, length: match.range.location - windowStart))
            let windowNs = window as NSString
            let rows     = rowStartRe.matches(in: window, range: NSRange(location: 0, length: windowNs.length))

            guard let last = rows.last,
                  last.range(at: 1).location != NSNotFound,
                  let effectId = Int(windowNs.substring(with: last.range(at: 1)))
            else { return }

            result[effectId, default: []].append(LGMPatch(
                modifiedAttrId:  modifiedAttrId,
                modifyingAttrId: modifyingAttrId,
                operatorId:      operation,
                groupId:         groupId,
                domain:          domain
            ))
        }

        let total = result.values.map(\.count).reduce(0, +)
        print("[SDEClient] SQL (JSON): \(total) LGM patches across \(result.count) effects")
        return result
    }

    /// Legacy format: modifier info in a dedicated table (dgmEffectModifiers / dgmEffectsModifierInfo)
    /// with one row per modifier, including explicit func/groupID columns.
    private func parseLegacySeparateTable(_ section: String) -> [Int: [LGMPatch]] {
        // 1. Extract column order from CREATE TABLE.
        var colOrder: [String] = []
        if let createRange = section.range(of: "CREATE TABLE", options: .caseInsensitive) {
            let createBlock = String(section[createRange.lowerBound...].prefix(3000))
            let colRe = try? NSRegularExpression(pattern: "`(\\w+)`\\s+[a-zA-Z]")
            let ns = createBlock as NSString
            colRe?.matches(in: createBlock, range: NSRange(location: 0, length: ns.length)).forEach { m in
                if m.range(at: 1).location != NSNotFound {
                    colOrder.append(ns.substring(with: m.range(at: 1)))
                }
            }
        }
        // Known SDE column order as fallback — try YAML SDE naming first, then legacy.
        if colOrder.isEmpty {
            colOrder = ["effectID","modifierID","func","domain","srcAttrID","tgtAttrID","operator","propulsion","groupID","skillTypeID"]
        }

        // YAML SDE uses camelCase column aliases — remap to the legacy names used by ColumnIndex.
        colOrder = colOrder.map { col in
            switch col {
            case "effectId":          return "effectID"
            case "modifiedAttributeID", "modifiedAttributeId", "tgtAttrId": return "tgtAttrID"
            case "modifyingAttributeID", "modifyingAttributeId", "srcAttrId": return "srcAttrID"
            case "operation":         return "operator"
            case "skillTypeId":       return "skillTypeID"
            default:                  return col
            }
        }

        let ci = ColumnIndex(from: colOrder)
        guard ci.isValid else {
            print("[SDEClient] SQL: invalid column index — colOrder=\(colOrder)")
            return [:]
        }
        print("[SDEClient] SQL columns: \(colOrder) → effectID@\(ci.effectID) func@\(ci.func_) groupID@\(ci.groupID)")

        // 2. Find the VALUES portion of the INSERT INTO statement.
        guard let insertIdx = section.range(of: "INSERT INTO", options: .caseInsensitive),
              let valuesIdx = section.range(of: "VALUES", options: .caseInsensitive, range: insertIdx.lowerBound..<section.endIndex),
              insertIdx.lowerBound < valuesIdx.lowerBound
        else {
            print("[SDEClient] SQL: no INSERT INTO … VALUES found")
            return [:]
        }
        let valuesStr = String(section[valuesIdx.upperBound...])

        // 3. Extract every (…) tuple and parse it.
        // `[^)]` matches any character including newlines, so multi-row INSERTs work.
        var result: [Int: [LGMPatch]] = [:]
        let tupleRe = try? NSRegularExpression(pattern: "\\(([^)]+)\\)")
        let ns = valuesStr as NSString
        tupleRe?.matches(in: valuesStr, range: NSRange(location: 0, length: ns.length)).forEach { m in
            let row = ns.substring(with: m.range(at: 1))
            let cols = row.components(separatedBy: ",").map { field -> String in
                let t = field.trimmingCharacters(in: .init(charactersIn: " '\"`"))
                return t == "NULL" ? "" : t
            }
            guard ci.func_ < cols.count, cols[ci.func_] == "LocationGroupModifier" else { return }
            guard ci.groupID  < cols.count, let groupId  = Int(cols[ci.groupID])  else { return }
            guard ci.effectID < cols.count, let effectId = Int(cols[ci.effectID]) else { return }

            let patch = LGMPatch(
                modifiedAttrId:  ci.tgtAttrID  < cols.count ? Int(cols[ci.tgtAttrID])  : nil,
                modifyingAttrId: ci.srcAttrID  < cols.count ? Int(cols[ci.srcAttrID])  : nil,
                operatorId:      ci.operator_  < cols.count ? Int(cols[ci.operator_])  : nil,
                groupId: groupId,
                domain: ci.domain < cols.count && !cols[ci.domain].isEmpty ? cols[ci.domain] : nil
            )
            result[effectId, default: []].append(patch)
        }

        let total = result.values.map(\.count).reduce(0, +)
        print("[SDEClient] SQL: \(total) LGM patches across \(result.count) effects")
        return result
    }

    // MARK: Column index helper

    private struct ColumnIndex {
        var effectID = -1, func_ = -1, domain = -1
        var srcAttrID = -1, tgtAttrID = -1, operator_ = -1, groupID = -1

        var isValid: Bool { effectID >= 0 && func_ >= 0 && groupID >= 0 }

        init() {}
        init(from headers: [String]) {
            for (i, h) in headers.enumerated() {
                switch h.trimmingCharacters(in: .whitespaces) {
                case "effectID":                effectID  = i
                case "func", "function":        func_     = i
                case "domain":                  domain    = i
                case "srcAttrID":               srcAttrID = i
                case "tgtAttrID":               tgtAttrID = i
                case "operator":                operator_ = i
                case "groupID":                 groupID   = i
                default: break
                }
            }
        }
    }

    // MARK: Disk cache

    private struct Meta: Codable { let savedDate: Date }

    private func loadFromDisk() -> [Int: [LGMPatch]]? {
        guard let metaData = try? Data(contentsOf: Self.metaURL),
              let meta = try? JSONDecoder().decode(Meta.self, from: metaData),
              Date().timeIntervalSince(meta.savedDate) < Self.ttl
        else { return nil }

        guard let data    = try? Data(contentsOf: Self.dataURL),
              let wrapped = try? JSONDecoder().decode([String: [LGMPatch]].self, from: data)
        else { return nil }

        return Dictionary(uniqueKeysWithValues: wrapped.compactMap { key, val in
            Int(key).map { ($0, val) }
        })
    }

    private func saveToDisk(_ p: [Int: [LGMPatch]]) {
        let wrapped = Dictionary(uniqueKeysWithValues: p.map { (String($0.key), $0.value) })
        if let data = try? JSONEncoder().encode(wrapped) {
            try? data.write(to: Self.dataURL, options: .atomic)
        }
        if let meta = try? JSONEncoder().encode(Meta(savedDate: Date())) {
            try? meta.write(to: Self.metaURL, options: .atomic)
        }
        print("[SDEClient] Saved LGM patches to disk")
    }
}
