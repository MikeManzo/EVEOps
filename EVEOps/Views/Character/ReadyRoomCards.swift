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

// MARK:  Tier presentation

extension ReadyRoomTier {
    var title: LocalizedStringKey {
        switch self {
        case .ready:   "Ready to Undock"
        case .travel:  "Travel Required"
        case .waiting: "Parts On the Way"
        case .buy:     "Buy Parts"
        case .train:   "Train First"
        case .blocked: "Won’t Fit"
        }
    }

    /// Short form for chips and tiles.
    var shortTitle: String {
        switch self {
        case .ready:   String(localized: "Ready")
        case .travel:  String(localized: "Travel")
        case .waiting: String(localized: "On the Way")
        case .buy:     String(localized: "Buy")
        case .train:   String(localized: "Train")
        case .blocked: String(localized: "Won’t Fit")
        }
    }

    var systemImage: String {
        switch self {
        case .ready:   "checkmark.seal.fill"
        case .travel:  "arrow.triangle.turn.up.right.diamond.fill"
        case .waiting: "shippingbox.and.arrow.backward.fill"
        case .buy:     "cart.fill"
        case .train:   "graduationcap.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    func color(_ palette: EVEPalette) -> Color {
        switch self {
        case .ready:   .green
        case .travel:  .cyan
        case .waiting: .teal
        case .buy:     .orange
        case .train:   palette.knowledge
        case .blocked: .red
        }
    }
}

extension ReadyRoomIncoming.Kind {
    var title: String {
        switch self {
        case .industry: String(localized: "Manufacturing")
        case .courier:  String(localized: "Courier")
        case .buyOrder: String(localized: "Buy order")
        }
    }

    var systemImage: String {
        switch self {
        case .industry: "hammer.fill"
        case .courier:  "shippingbox.fill"
        case .buyOrder: "cart.badge.plus"
        }
    }
}

// MARK:  Shared formatting

enum ReadyRoomFormat {
    static func duration(_ seconds: Double) -> String {
        seconds < 60 ? String(localized: "<1m") : EVEFormatters.formatDuration(Int(seconds))
    }

    static func jumps(_ count: Int) -> String {
        count == 0 ? String(localized: "Same system") : String(localized: "\(count) jumps")
    }

    static func roman(_ level: Int) -> String {
        ["0", "I", "II", "III", "IV", "V"][min(max(level, 0), 5)]
    }

    /// "Oct 5, 14:20", or "queue paused" for a queue with no finish date.
    static func queuedDate(_ date: Date) -> String {
        date == .distantFuture
            ? String(localized: "queue paused")
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func percent(_ used: Double, of total: Double) -> String {
        guard total > 0 else { return "—" }
        return (used / total).formatted(.percent.precision(.fractionLength(0)))
    }
}

// MARK:  Card

struct ReadyRoomCard: View {
    let report: ReadyRoomReport
    let isSelected: Bool
    var isPinned = false
    var fitCheck: ReadyRoomSnapshot.FittingCheckState = .done

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(EVESpacing.lg)
                .eveHeroBackdrop(EVEImageURL.typeRender(report.shipTypeID, size: 512),
                                 height: 76, cornerRadius: EVERadius.xl, intensity: 0.45)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: EVESpacing.sm) {
                ReadyRoomSkillLane(report: report)
                ReadyRoomFitLane(report: report, state: fitCheck)
                ReadyRoomPartsLane(report: report)
                ReadyRoomPlaceLane(report: report)
            }
            .padding(EVESpacing.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .eveCard(cornerRadius: EVERadius.xl)
        .eveHoverable(cornerRadius: EVERadius.xl)
        .eveSelectionGlow(isActive: isSelected, cornerRadius: EVERadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var header: some View {
        HStack(spacing: EVESpacing.lg) {
            CachedAsyncImage(url: EVEImageURL.typeRender(report.shipTypeID, size: 256)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: EVERadius.sm).fill(.quaternary)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: EVERadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: EVERadius.sm)
                    .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: EVESpacing.xs) {
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.eveMicro)
                            .foregroundStyle(themeManager.palette.accent)
                            .accessibilityLabel("Pinned")
                    }
                    Text(report.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .eveTruncationHelp(report.name)
                }
                Text(verbatim: "\(report.shipTypeName) · \(report.shipClassName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: EVESpacing.sm)

            let tint = report.tier.color(themeManager.palette)
            Image(systemName: report.tier.systemImage)
                .font(.eveSubsectionTitle)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(EVEOpacity.soft), in: RoundedRectangle(cornerRadius: EVERadius.md))
                .help(Text(report.tier.title))
                .accessibilityLabel(Text(report.tier.title))
        }
    }
}

// MARK:  Lanes

/// One status line on a card: icon, fixed-width label, value, optional trailing detail.
private struct ReadyRoomLane<Value: View, Trailing: View>: View {
    let icon: String
    let tint: Color
    let label: LocalizedStringKey
    @ViewBuilder var value: () -> Value
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: EVESpacing.md) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(label)
                .font(.eveCaptionMedium)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            value()
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: EVESpacing.xs)
            trailing()
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

extension ReadyRoomLane where Trailing == EmptyView {
    init(icon: String, tint: Color, label: LocalizedStringKey, @ViewBuilder value: @escaping () -> Value) {
        self.init(icon: icon, tint: tint, label: label, value: value) { EmptyView() }
    }
}

struct ReadyRoomSkillLane: View {
    let report: ReadyRoomReport
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        let gaps = report.unqueuedGaps
        if report.isFlyable {
            ReadyRoomLane(icon: "checkmark.circle.fill", tint: .green, label: "Skills") {
                Text("All trained")
            }
        } else if report.needsOmega && gaps.isEmpty {
            ReadyRoomLane(icon: "lock.fill", tint: .yellow, label: "Skills") {
                Text("Omega required")
            }
        } else if gaps.isEmpty, let until = report.queuedUntil {
            ReadyRoomLane(icon: "clock.fill", tint: themeManager.palette.knowledge, label: "Skills") {
                Text("In queue · \(ReadyRoomFormat.queuedDate(until))")
            }
        } else {
            let untrained = gaps.contains { $0.trainedLevel == 0 }
            ReadyRoomLane(icon: untrained ? "xmark.circle.fill" : "arrow.up.circle.fill",
                          tint: untrained ? .red : .orange, label: "Skills") {
                if report.needsOmega {
                    Text("\(gaps.count) to train · Omega")
                } else {
                    Text("\(gaps.count) to train")
                }
            } trailing: {
                if let seconds = report.trainingSeconds {
                    Text(ReadyRoomFormat.duration(seconds))
                }
            }
        }
    }
}

struct ReadyRoomFitLane: View {
    let report: ReadyRoomReport
    let state: ReadyRoomSnapshot.FittingCheckState

    var body: some View {
        if let check = report.fitting {
            let cpu = ReadyRoomFormat.percent(check.cpuUsed, of: check.cpuTotal)
            let power = ReadyRoomFormat.percent(check.powerUsed, of: check.powerTotal)
            if check.fitsNow {
                ReadyRoomLane(icon: "checkmark.circle.fill", tint: .green, label: "Fit") {
                    Text("Fits")
                } trailing: {
                    Text(verbatim: "CPU \(cpu) · PG \(power)")
                }
            } else if check.fitsWithTraining {
                ReadyRoomLane(icon: "cpu", tint: .orange, label: "Fit") {
                    Text("Needs fitting skills")
                } trailing: {
                    Text(verbatim: "CPU \(cpu) · PG \(power)")
                }
            } else {
                ReadyRoomLane(icon: "xmark.octagon.fill", tint: .red, label: "Fit") {
                    Text("Over budget even at V")
                } trailing: {
                    Text(verbatim: "CPU \(cpu) · PG \(power)")
                }
            }
        } else {
            ReadyRoomLane(icon: "cpu", tint: .secondary, label: "Fit") {
                Group {
                    switch state {
                    case .pending: Text("Checking…")
                    case .unavailable, .done: Text("Not checked")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
    }
}

struct ReadyRoomPartsLane: View {
    let report: ReadyRoomReport

    var body: some View {
        let elsewhere = report.requiredParts.reduce(0) { $0 + $1.elsewhereQuantity }
        let corp = report.corporationCount
        if report.missingCount == 0 && elsewhere == 0 && report.incomingCount == 0 {
            ReadyRoomLane(icon: "checkmark.circle.fill", tint: .green, label: "Parts") {
                Text("All \(report.requiredCount) together")
            } trailing: {
                if corp > 0 { Text("\(corp) corp") }
            }
        } else if report.missingCount == 0 && report.incomingCount > 0 {
            ReadyRoomLane(icon: "shippingbox.and.arrow.backward.fill", tint: .teal, label: "Parts") {
                Text("\(report.incomingCount) on the way")
            } trailing: {
                if let eta = report.requiredParts.flatMap(\.incoming).compactMap(\.eta).max() {
                    Text(EVEFormatters.timeUntil(eta))
                }
            }
        } else if report.missingCount == 0 {
            ReadyRoomLane(icon: "shippingbox.fill", tint: .cyan, label: "Parts") {
                Text("All owned · \(elsewhere) elsewhere")
            } trailing: {
                if corp > 0 { Text("\(corp) corp") }
            }
        } else {
            ReadyRoomLane(icon: "cart.fill", tint: .orange, label: "Parts") {
                Text("\(report.ownedCount)/\(report.requiredCount) owned")
            } trailing: {
                if let isk = report.missingISK {
                    Text(EVEFormatters.formatISKShort(isk))
                }
            }
        }
    }
}

struct ReadyRoomPlaceLane: View {
    let report: ReadyRoomReport

    var body: some View {
        if let place = report.staging {
            ReadyRoomLane(icon: report.isStagingCurrentLocation ? "location.fill" : "mappin.circle.fill",
                          tint: report.isStagingCurrentLocation ? .green : .secondary,
                          label: "Place") {
                HStack(spacing: EVESpacing.xs) {
                    if let security = place.security {
                        EVESecurityBadge(status: security, compact: true)
                    }
                    Text(report.isStagingCurrentLocation ? String(localized: "Here") : place.systemName ?? place.name)
                        .eveTruncationHelp(place.name)
                    if report.hasJumpCloneAtStaging && !report.isStagingCurrentLocation {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundStyle(.cyan)
                            .help("One of your jump clones is in this station")
                            .accessibilityLabel("Jump clone here")
                    }
                }
            } trailing: {
                if !report.isStagingCurrentLocation, let jumps = report.stagingJumps {
                    Text(ReadyRoomFormat.jumps(jumps))
                }
            }
        } else {
            ReadyRoomLane(icon: "mappin.slash", tint: .secondary, label: "Place") {
                Text("Nothing owned yet").foregroundStyle(.secondary)
            }
        }
    }
}
