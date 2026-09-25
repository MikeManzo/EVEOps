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

/// Finds release notes to show once after an update. The notes are the ones already
/// written for Sparkle: the `<description>` of the appcast item matching the running
/// version, fetched from the same `SUFeedURL` Sparkle uses — so there's nothing extra to
/// maintain per release.
nonisolated enum WhatsNewService {
    struct Notes: Identifiable, Sendable {
        let version: String
        let items: [String]
        var id: String { version }

        var releaseURL: URL? { URL(string: "https://github.com/MikeManzo/EVEOps/releases/tag/v\(version)") }
    }

    static let lastSeenKey = "whatsNew.lastSeenVersion"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// Notes for the running version if the user hasn't seen them yet; nil otherwise.
    /// A fresh install (no pilots) just records the version — it gets onboarding instead.
    static func pendingNotes(hasAccounts: Bool) async -> Notes? {
        let version = currentVersion
        let defaults = UserDefaults.standard
        guard !version.isEmpty, defaults.string(forKey: lastSeenKey) != version else { return nil }
        guard hasAccounts else {
            markSeen()
            return nil
        }
        guard let feed = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              let url = URL(string: feed),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let html = AppcastNotesParser.description(forVersion: version, in: data) else {
            // Offline or no matching entry: try again next launch rather than skipping.
            return nil
        }
        let items = listItems(fromHTML: html)
        guard !items.isEmpty else {
            markSeen()
            return nil
        }
        return Notes(version: version, items: items)
    }

    /// The newest published release notes, whatever version is running — for
    /// Help › What's New in EVEOps. Nil when the feed can't be reached.
    static func latestNotes() async -> Notes? {
        guard let feed = Bundle.main.infoDictionary?["SUFeedURL"] as? String,
              let url = URL(string: feed),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let latest = AppcastNotesParser.newest(in: data) else { return nil }
        let items = listItems(fromHTML: latest.html)
        return items.isEmpty ? nil : Notes(version: latest.version, items: items)
    }

    static func markSeen() {
        UserDefaults.standard.set(currentVersion, forKey: lastSeenKey)
    }

    /// The `<li>` entries of the release-notes HTML as plain strings (the release script
    /// writes notes as a bullet list); falls back to `<p>` paragraphs.
    static func listItems(fromHTML html: String) -> [String] {
        func matches(_ tag: String) -> [String] {
            let pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
            let range = NSRange(html.startIndex..., in: html)
            return regex.matches(in: html, range: range).compactMap { match in
                Range(match.range(at: 1), in: html).map { plainText(String(html[$0])) }
            }.filter { !$0.isEmpty }
        }
        let items = matches("li")
        return items.isEmpty ? matches("p") : items
    }

    private static func plainText(_ fragment: String) -> String {
        var text = fragment.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, char) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            text = text.replacingOccurrences(of: entity, with: char)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Pulls the `<description>` of the appcast `<item>` whose `sparkle:shortVersionString`
/// matches a version.
private nonisolated final class AppcastNotesParser: NSObject, XMLParserDelegate {
    /// Version to match, or nil to take the first (newest) item in the feed.
    private let version: String?
    private var inItem = false
    private var element = ""
    private var itemVersion = ""
    private var itemDescription = ""
    private(set) var result: String?
    private(set) var resultVersion: String?

    private init(version: String?) { self.version = version }

    /// The first (newest) item's version and notes.
    static func newest(in data: Data) -> (version: String, html: String)? {
        let delegate = AppcastNotesParser(version: nil)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let html = delegate.result, let version = delegate.resultVersion else { return nil }
        return (version, html)
    }

    static func description(forVersion version: String, in data: Data) -> String? {
        let delegate = AppcastNotesParser(version: version)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        if elementName == "item" {
            inItem = true
            itemVersion = ""
            itemDescription = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        if element == "sparkle:shortVersionString" { itemVersion += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard inItem, element == "description", let text = String(data: CDATABlock, encoding: .utf8) else { return }
        itemDescription += text
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            inItem = false
            let trimmed = itemVersion.trimmingCharacters(in: .whitespacesAndNewlines)
            if (version == nil || trimmed == version), !itemDescription.isEmpty {
                result = itemDescription
                resultVersion = trimmed
                parser.abortParsing()
            }
        }
        element = ""
    }
}
