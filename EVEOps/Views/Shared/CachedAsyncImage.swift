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
import CryptoKit
import AppKit

/// Process-wide image cache (memory + disk) for CCP's image server art.
///
/// `AsyncImage` only ever hits `URLCache`, so portraits and type icons re-decode
/// and often re-download every time a row scrolls back into view. This keeps a
/// decoded `NSImage` in memory and the raw bytes on disk, so the second showing
/// of any image is instant and offline-safe.
@MainActor
final class ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private let directory: URL
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    private init() {
        memory.countLimit = 500
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("EVEOps/images", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Synchronous memory-only lookup — lets a view paint a cached image on the
    /// very first frame instead of flashing its placeholder.
    func cachedImage(for url: URL) -> NSImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    /// Returns the image for `url`, loading from disk or network as needed.
    /// Concurrent callers for the same URL share one load.
    func image(for url: URL) async -> NSImage? {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }

        let data: Data?
        if let existing = inFlight[url] {
            data = await existing.value
        } else {
            let fileURL = directory.appendingPathComponent(Self.filename(for: url))
            let task = Task.detached(priority: .utility) { () -> Data? in
                if let disk = try? Data(contentsOf: fileURL) { return disk }
                guard let (bytes, response) = try? await URLSession.shared.data(from: url),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else { return nil }
                try? bytes.write(to: fileURL, options: .atomic)
                return bytes
            }
            inFlight[url] = task
            data = await task.value
            inFlight.removeValue(forKey: url)
        }

        guard let data, let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// Wipe both tiers. Wired to the existing "clear caches" control in Settings.
    func clear() {
        memory.removeAllObjects()
        let dir = directory
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private static func filename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Drop-in replacement for `AsyncImage` backed by ``ImageCache``.
///
/// Both `AsyncImage` initializer shapes are mirrored, so call sites migrate with
/// a plain `AsyncImage(` → `CachedAsyncImage(` rename.
struct CachedAsyncImage<Content: View>: View {
    private let url: URL?
    private let scale: CGFloat
    private let transaction: Transaction
    private let content: (AsyncImagePhase) -> Content

    @State private var phase: AsyncImagePhase = .empty

    init(
        url: URL?,
        scale: CGFloat = 1,
        transaction: Transaction = Transaction(),
        @ViewBuilder content: @escaping (AsyncImagePhase) -> Content
    ) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        if let cached = ImageCache.shared.cachedImage(for: url) {
            phase = .success(Image(nsImage: cached))
            return
        }
        phase = .empty
        let image = await ImageCache.shared.image(for: url)
        guard !Task.isCancelled else { return }
        withTransaction(transaction) {
            phase = image.map { .success(Image(nsImage: $0)) }
                ?? .failure(URLError(.cannotDecodeContentData))
        }
    }
}

extension CachedAsyncImage {
    /// Mirrors `AsyncImage.init(url:scale:content:placeholder:)`.
    init<I: View, P: View>(
        url: URL?,
        scale: CGFloat = 1,
        @ViewBuilder content: @escaping (Image) -> I,
        @ViewBuilder placeholder: @escaping () -> P
    ) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale) { phase in
            if let image = phase.image {
                content(image)
            } else {
                placeholder()
            }
        }
    }
}

extension CachedAsyncImage where Content == Image {
    /// Mirrors `AsyncImage.init(url:scale:)`.
    init(url: URL?, scale: CGFloat = 1) {
        self.init(url: url, scale: scale) { phase in
            phase.image ?? Image(nsImage: NSImage())
        }
    }
}
