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

struct CharacterBookmarksView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var folders: [ESIBookmarkFolder] = []
    @State private var bookmarks: [ESIBookmark] = []
    @State private var locationNames: [Int: String] = [:]
    @State private var selectedFolderId: Int? = nil  // nil = all, -1 = uncategorized
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var error: String?

    private var visibleBookmarks: [ESIBookmark] {
        var result = bookmarks
        if let folderId = selectedFolderId {
            if folderId == -1 {
                result = result.filter { $0.folderId == nil }
            } else {
                result = result.filter { $0.folderId == folderId }
            }
        }
        if !searchText.isEmpty {
            result = result.filter {
                ($0.label ?? "").localizedCaseInsensitiveContains(searchText) ||
                ($0.memo ?? "").localizedCaseInsensitiveContains(searchText) ||
                locationNames[$0.locationId]?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        return result.sorted { $0.created > $1.created }
    }

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: bookmarks.isEmpty, emptyMessage: "No bookmarks found") {
            VStack(spacing: 0) {
                folderBar
                Divider()
                bookmarkList
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Bookmarks")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Bookmarks (\(bookmarks.count))")
        .searchable(text: $searchText, prompt: "Search bookmarks")
        .task(id: accountManager.selectedCharacterID) {
            await loadBookmarks()
        }
    }

    // MARK:  Folder Bar

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                folderChip(name: "All", folderId: nil, count: bookmarks.count)
                ForEach(folders.sorted { ($0.name ?? "") < ($1.name ?? "") }) { folder in
                    let count = bookmarks.filter { $0.folderId == folder.folderId }.count
                    folderChip(name: folder.name ?? "Unnamed", folderId: folder.folderId, count: count)
                }
                let uncatCount = bookmarks.filter { $0.folderId == nil }.count
                if uncatCount > 0 && !folders.isEmpty {
                    folderChip(name: "Uncategorized", folderId: -1, count: uncatCount)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private func folderChip(name: String, folderId: Int?, count: Int) -> some View {
        let isSelected = selectedFolderId == folderId
        return Button {
            selectedFolderId = folderId
        } label: {
            HStack(spacing: 5) {
                Text(name)
                    .font(.caption)
                Text("\(count)")
                    .font(.system(size: 9))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(isSelected ? Color.accentColor : Color.gray.opacity(0.25), in: Capsule())
                    .foregroundStyle(isSelected ? Color.white : Color.gray)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK:  Bookmark List

    private var bookmarkList: some View {
        List(visibleBookmarks) { bookmark in
            BookmarkRow(bookmark: bookmark, locationName: locationNames[bookmark.locationId])
        }
    }

    // MARK:  Loading

    private func loadBookmarks() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let token = try await accountManager.validToken(for: account)
            async let fetchFolders: [ESIBookmarkFolder] = ESIClient.shared.fetch(
                "/characters/\(account.characterID)/bookmarks/folders/", token: token
            )
            async let fetchBookmarks: [ESIBookmark] = ESIClient.shared.fetchPages(
                "/characters/\(account.characterID)/bookmarks/", token: token
            )
            let (f, b) = try await (fetchFolders, fetchBookmarks)
            folders = f
            bookmarks = b
            let locationIds = Array(Set(b.map { $0.locationId }))
            locationNames = await NameResolver.shared.resolve(ids: locationIds)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK:  Bookmark Row

struct BookmarkRow: View {
    let bookmark: ESIBookmark
    let locationName: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.label ?? "Unnamed Bookmark")
                    .font(.subheadline)
                    .lineLimit(1)
                Text(locationName ?? "Unknown Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let memo = bookmark.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let coords = bookmark.coordinates {
                    Text(String(format: "%.2e", coords.x))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text(bookmark.created, style: .date)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        if bookmark.item != nil { return "dot.circle" }
        if bookmark.coordinates != nil { return "mappin.and.ellipse" }
        return "bookmark.fill"
    }
}
