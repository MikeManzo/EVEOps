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

// MARK:  EVE News Widget

struct EVENewsWidgetView: View {
    let items: [EVENewsItem]
    let isLoading: Bool
    @Binding var isExpanded: Bool
    @Binding var readIDs: Set<String>

    private var unreadCount: Int { items.filter { !readIDs.contains($0.id) }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "newspaper.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Text("EVE News")
                        .font(.title3.bold())
                    if unreadCount > 0 {
                        Text("\(unreadCount)")
                            .font(.caption.bold())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading news...")
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if items.isEmpty {
                    HStack {
                        Spacer()
                        Text("Unable to load EVE news")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else {
                    let columns = [GridItem(.adaptive(minimum: 300, maximum: 480), spacing: 12)]
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(items) { item in
                            NewsCardView(item: item, readIDs: $readIDs)
                        }
                    }
                    .padding(.top, 12)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct NewsCardView: View {
    let item: EVENewsItem
    @Binding var readIDs: Set<String>
    @Environment(\.openURL) private var openURL

    private var isRead: Bool { readIDs.contains(item.id) }

    var body: some View {
        Button {
            if let url = item.link {
                readIDs.insert(item.id)
                openURL(url)
            }
        } label: {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(categoryColor)
                    .frame(height: 3)

                bannerView
                    .frame(height: 60)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if !isRead {
                            Circle()
                                .fill(.blue)
                                .frame(width: 10, height: 10)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                                .padding(6)
                        }
                    }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(item.category.isEmpty ? "EVE News" : item.category)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor.opacity(0.15), in: Capsule())
                            .foregroundStyle(categoryColor)
                            .lineLimit(1)

                        Spacer()

                        if let date = item.pubDate {
                            Text(date, style: .relative)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(item.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    let snippet = plainSummary
                    if !snippet.isEmpty {
                        Text(snippet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Divider()

                    HStack {
                        Label(item.author.isEmpty ? "CCP Games" : item.author, systemImage: "person.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "arrow.up.right.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bannerView: some View {
        if let imageURL = bannerImageURL {
            CachedAsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Color.black.opacity(0.55)],
                                startPoint: .init(x: 0.5, y: 0.3),
                                endPoint: .bottom
                            )
                        )
                default:
                    categoryGradientBanner
                }
            }
        } else {
            categoryGradientBanner
        }
    }

    private var categoryGradientBanner: some View {
        ZStack {
            LinearGradient(
                colors: [categoryColor.opacity(0.35), Color(white: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: categoryIcon)
                .font(.system(size: 36))
                .foregroundStyle(categoryColor.opacity(0.25))
        }
    }

    private var bannerImageURL: URL? {
        let pattern = #"<img[^>]+src="(https[^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                  in: item.summary,
                  range: NSRange(item.summary.startIndex..., in: item.summary)
              ),
              let srcRange = Range(match.range(at: 1), in: item.summary) else {
            return nil
        }
        return URL(string: String(item.summary[srcRange]))
    }

    private var categoryIcon: String {
        let lower = item.category.lowercased()
        if lower.contains("dev")   { return "wrench.and.screwdriver.fill" }
        if lower.contains("event") { return "calendar.badge.plus" }
        return "megaphone.fill"
    }

    private var categoryColor: Color {
        let lower = item.category.lowercased()
        if lower.contains("dev")    { return .purple }
        if lower.contains("event")  { return .orange }
        return .blue
    }

    private var plainSummary: String {
        var text = item.summary
        text = text.replacingOccurrences(
            of: "<div[^>]*class=\"lightbox-wrapper\"[^>]*>[\\s\\S]*?</div>",
            with: " ", options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(of: "<br[^>]*>", with: " ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: " ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities: [(String, String)] = [
            ("&amp;","&"), ("&lt;","<"), ("&gt;",">"),
            ("&quot;","\""), ("&#39;","'"), ("&nbsp;"," "), ("&#32;"," ")
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        if let range = text.range(of: #"\d+ posts? - \d+ participants?"#, options: .regularExpression) {
            text = String(text[..<range.lowerBound])
        }
        if text.count > 260 {
            text = String(text.prefix(260))
            if let last = text.lastIndex(of: ".") {
                text = String(text[...last])
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
