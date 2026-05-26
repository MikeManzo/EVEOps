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

// MARK: Model

struct EVENewsItem: Identifiable, Sendable {
    let id: String
    let title: String
    let link: URL?
    let summary: String
    let pubDate: Date?
    let category: String
    let author: String      // dc:creator — e.g. "CCP Swift"
}

// MARK: Client

actor EVENewsClient {
    static let shared = EVENewsClient()

    private let session: URLSession
    private var cache: [EVENewsItem] = []
    private var cacheExpiry: Date = .distantPast

    private static let cacheDuration: TimeInterval = 15 * 60

    // Official CCP news: EVE Information Portal category on the EVE Forums (Discourse).
    // Contains Dev Blogs + Announcements subcategories, all authored by CCP staff.
    private static let feedURL = URL(string: "https://forums.eveonline.com/c/eve-information-portal/80.rss")!

    private init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept":     "application/rss+xml, application/xml, text/xml",
            "User-Agent": "EVEOps macOS App"
        ]
        session = URLSession(configuration: config)
    }

    func fetchNews(limit: Int = 8) async throws -> [EVENewsItem] {
        if Date() < cacheExpiry, !cache.isEmpty {
            return Array(cache.prefix(limit))
        }

        let (data, response) = try await session.data(from: Self.feedURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return Array(cache.prefix(limit))
        }

        let items = await MainActor.run { RSSParser().parse(data: data) }
        cache = items
        cacheExpiry = Date().addingTimeInterval(Self.cacheDuration)
        return Array(items.prefix(limit))
    }
}

// MARK: RSS Parser

@MainActor
private final class RSSParser: NSObject, XMLParserDelegate {
    private var items: [EVENewsItem] = []
    private var insideItem = false
    private var currentElement = ""
    private var buffer = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentPubDate = ""
    private var currentCategory = ""
    private var currentGuid = ""
    private var currentAuthor = ""

    private static let pubDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f
    }()

    func parse(data: Data) -> [EVENewsItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        buffer = ""
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentLink = ""
            currentDescription = ""
            currentPubDate = ""
            currentCategory = ""
            currentGuid = ""
            currentAuthor = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        buffer += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard insideItem, let str = String(data: CDATABlock, encoding: .utf8) else { return }
        buffer += str
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if insideItem {
            switch elementName {
            case "title":       currentTitle       = value
            case "link":        currentLink        = value
            case "description": currentDescription = value
            case "pubDate":     currentPubDate     = value
            case "category":    currentCategory    = value
            case "guid":        currentGuid        = value
            case "dc:creator":  currentAuthor      = value
            case "item":
                let id = currentGuid.isEmpty ? currentLink : currentGuid
                let date = Self.pubDateFormatter.date(from: currentPubDate)
                items.append(EVENewsItem(
                    id: id,
                    title: currentTitle,
                    link: URL(string: currentLink),
                    summary: currentDescription,
                    pubDate: date,
                    category: currentCategory,
                    author: currentAuthor
                ))
                insideItem = false
            default:
                break
            }
        }
        buffer = ""
    }
}
