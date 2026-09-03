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
import Charts
import FoundationModels

struct MarketGroupNode: Identifiable {
    let group: ESIMarketGroup
    var children: [MarketGroupNode]?
    var id: Int { group.marketGroupId }
}

struct MarketTypeResult: Identifiable {
    let typeId: Int
    let name: String
    var id: Int { typeId }
}

struct ResolvedOrder: Identifiable {
    let order: ESIRegionMarketOrder
    var locationName: String
    var systemName: String
    var securityStatus: Double
    var jumps: Int?
    var id: Int { order.orderId }
}

enum OrderSortKey: Equatable {
    case price, quantity, minVolume, location, security, jumps, range
}

// MARK:  SplitDivider (NSView-backed for jitter-free dragging)
//
// SwiftUI's DragGesture can lose its internal translation state when the parent
// view re-renders mid-drag, causing the pane to snap back. By routing mouse
// events through NSView instead, startValue and startPoint live on a stable
// Objective-C object that SwiftUI never recreates during re-renders.

class DragHandleNSView: NSView {
    var isHorizontal = true
    /// Updated by NSViewRepresentable.updateNSView on every render.
    var currentValue: CGFloat = 0
    var minValue: CGFloat = 0
    var maxValue: CGFloat = .greatestFiniteMagnitude
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    private var startValue: CGFloat = 0   // pane size captured at mouseDown
    private var startPoint: NSPoint?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeInActiveApp],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        (isHorizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        startValue = currentValue
        startPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = startPoint else { return }
        let pt = event.locationInWindow
        // NSView y=0 is at bottom: dragging DOWN decreases y → negative offset →
        // detailHeight shrinks, which is correct (divider moves toward detail pane).
        let offset = isHorizontal ? pt.x - start.x : pt.y - start.y
        let newValue = max(minValue, min(maxValue, startValue + offset))
        onDrag?(newValue)
    }

    override func mouseUp(with event: NSEvent) {
        startPoint = nil
        onEnd?()
    }
}

struct DragHandle: NSViewRepresentable {
    let isHorizontal: Bool
    let value: CGFloat
    let minValue: CGFloat
    let maxValue: CGFloat
    let onChange: (CGFloat) -> Void
    var onEnd: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragHandleNSView {
        let v = DragHandleNSView()
        apply(to: v)
        return v
    }

    func updateNSView(_ v: DragHandleNSView, context: Context) {
        apply(to: v)
    }

    private func apply(to v: DragHandleNSView) {
        v.isHorizontal = isHorizontal
        v.currentValue = value
        v.minValue = minValue
        v.maxValue = maxValue
        v.onDrag = onChange
        v.onEnd = onEnd
    }
}

struct SplitDivider: View {
    enum Direction { case horizontal, vertical }
    let direction: Direction
    let value: CGFloat
    let minValue: CGFloat
    let maxValue: CGFloat
    let onChange: (CGFloat) -> Void
    var onEnd: (() -> Void)? = nil

    var body: some View {
        ZStack {
            // Visual separator (SwiftUI — adapts to dark/light mode automatically)
            Color(NSColor.separatorColor)
                .frame(width: direction == .horizontal ? 1 : nil,
                       height: direction == .vertical   ? 1 : nil)
            // Transparent NSView hit-target — handles all mouse events
            DragHandle(isHorizontal: direction == .horizontal,
                       value: value, minValue: minValue, maxValue: maxValue,
                       onChange: onChange, onEnd: onEnd)
        }
        .frame(width: direction == .horizontal ? 8 : nil,
               height: direction == .vertical   ? 8 : nil)
    }
}

// MARK:  Type Image (render → icon fallback, with caching)

enum MarketTypeImageCache {
    static let shared = NSCache<NSNumber, NSImage>()
}

struct MarketTypeImage: View {
    let typeId: Int
    let size: CGFloat
    let cornerRadius: CGFloat

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Image(systemName: "cube.transparent")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(.tertiary)
                    .frame(width: size, height: size)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius).fill(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: typeId) {
            if let cached = MarketTypeImageCache.shared.object(forKey: NSNumber(value: typeId)) {
                image = cached
                return
            }
            image = nil
            failed = false
            if let loaded = await loadBestImage() {
                MarketTypeImageCache.shared.setObject(loaded, forKey: NSNumber(value: typeId))
                image = loaded
            } else {
                failed = true
            }
        }
    }

    private func loadBestImage() async -> NSImage? {
        if let url = EVEImageURL.typeRender(typeId, size: 256),
           let img = await fetch(url) { return img }
        if let url = EVEImageURL.typeIcon(typeId, size: 64),
           let img = await fetch(url) { return img }
        return nil
    }

    private func fetch(_ url: URL) async -> NSImage? {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return NSImage(data: data)
    }
}

// Mark:  Market AI Insight Card

@available(macOS 26.0, *)
struct MarketAIInsightCard: View {
    let itemName: String
    let regionName: String
    let resetKey: String
    let sellOrders: [ResolvedOrder]
    let buyOrders: [ResolvedOrder]
    let priceHistory: [ESIMarketHistory]
    let adjustedPrice: Double?
    let averagePrice: Double?

    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false
    @AppStorage("aiInsightMarket")   private var aiInsightMarket   = true
    @State private var insight: MarketInsight?
    @State private var isGenerating = false
    @State private var generationError: String?

    private var model: SystemLanguageModel { .default }

    var body: some View {
        if aiInsightsEnabled && aiInsightMarket, case .available = model.availability {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI Insight", systemImage: "sparkles")
                        .font(.subheadline.bold())
                        .foregroundStyle(.purple)
                    Spacer()
                    if insight != nil, !isGenerating {
                        Button {
                            Task { await generate() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Regenerate insight")
                    }
                }

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Analyzing market\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let insight {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.summary)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .padding(.top, 1)
                            Text(insight.suggestion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else if let error = generationError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.8))
                } else {
                    Button("Generate Insight") {
                        Task { await generate() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.purple.opacity(0.2)))
            .task(id: resetKey) {
                guard !resetKey.isEmpty else { return }
                insight = nil
                generationError = nil
                await generate()
            }
        }
    }

    private func generate() async {
        isGenerating = true
        generationError = nil

        let bestSell = sellOrders.first?.order.price
        let bestBuy = buyOrders.first?.order.price
        let spread: Double
        if let s = bestSell, let b = bestBuy, s > 0 {
            spread = ((s - b) / s) * 100
        } else {
            spread = 0
        }

        let recentHistory = priceHistory.suffix(30)
        let half = recentHistory.count / 2
        let priceChange30d: Double
        if half > 0 {
            let firstSlice = recentHistory.prefix(half).map { $0.average }
            let lastSlice = recentHistory.suffix(half).map { $0.average }
            let firstAvg = firstSlice.reduce(0, +) / Double(firstSlice.count)
            let lastAvg = lastSlice.reduce(0, +) / Double(lastSlice.count)
            priceChange30d = firstAvg > 0 ? ((lastAvg - firstAvg) / firstAvg) * 100 : 0
        } else {
            priceChange30d = 0
        }

        let fiveDayVols = priceHistory.suffix(5).map { Double($0.volume) }
        let avgVol = fiveDayVols.isEmpty ? 0 : Int(fiveDayVols.reduce(0, +) / Double(fiveDayVols.count))

        do {
            insight = try await IntelligenceService.shared.analyzeMarket(
                itemName: itemName,
                regionName: regionName,
                bestSell: bestSell.map { EVEFormatters.formatISKShort($0) } ?? "no sell orders",
                bestBuy: bestBuy.map { EVEFormatters.formatISKShort($0) } ?? "no buy orders",
                spreadPercent: spread,
                sellOrderCount: sellOrders.count,
                buyOrderCount: buyOrders.count,
                avgDailyVolume: avgVol,
                priceChange30dPercent: priceChange30d,
                adjustedPrice: adjustedPrice.map { EVEFormatters.formatISKShort($0) },
                globalAveragePrice: averagePrice.map { EVEFormatters.formatISKShort($0) }
            )
        } catch {
            generationError = "Unable to generate insight. Try again later."
        }
        isGenerating = false
    }
}
