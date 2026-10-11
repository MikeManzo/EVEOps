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

// MARK:  Wording

/// Turns an `EscapeCheck` into plain-language lines. Kept apart from the view so the
/// wording reads in one place.
enum EscapeCheckText {
    static func seconds(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    static func headline(_ check: EscapeCheck) -> String {
        switch check.verdict {
        case .warpsCloaked: "Camps can't catch you if you cloak"
        case .hardToCatch: "Most gate camps can't lock you in time"
        case .catchableByFastLockers: "A fast-locking camp can catch you"
        case .catchable: "A gate camp will probably catch you"
        }
    }

    static func stats(_ check: EscapeCheck) -> String {
        let ship = check.shipTypeName ?? "Your ship"
        let warp = check.warpSpeed.formatted(.number.precision(.fractionLength(1)))
        return "\(ship) aligns in \(seconds(check.alignTime)) (\(check.alignTicks) server tick\(check.alignTicks == 1 ? "" : "s")) "
            + "and warps at \(warp) AU/s."
    }

    static func explanation(_ check: EscapeCheck) -> String {
        switch check.verdict {
        case .warpsCloaked:
            return "Your covert ops cloak lets you warp while cloaked, so a camp never gets a lock."
        case .hardToCatch:
            return "You're in warp after \(check.alignTicks == 1 ? "one second" : "two seconds"), "
                + "before nearly any camp can lock you. Leave gate cloak by warping straight away, "
                + "not by moving first."
        case .catchableByFastLockers:
            return "Taking \(check.alignTicks) seconds to align is long enough for a camp's fast-locking ships "
                + "to catch you, though slower ones may miss."
        case .catchable:
            return "Taking \(check.alignTicks) seconds to align gives any camp time to lock and point you."
        }
    }

    static func suggestion(_ suggestion: EscapeSuggestion) -> String {
        switch suggestion {
        case .warpCloaked:
            return "After a jump, cloak as soon as you move, align, and warp. Decloak only once you've landed."
        case .useCloakTrick:
            return "Use the MWD+cloak trick: after the jump, align, start the microwarpdrive and cloak "
                + "together, then decloak and warp as the MWD cycle ends."
        case .addMicrowarpdrive:
            return "You have a cloak but no microwarpdrive. Fitting one lets you do the MWD+cloak trick, "
                + "which beats most camps."
        case .addCloak:
            return "You have a microwarpdrive. Adding a Prototype Cloaking Device lets you do the MWD+cloak trick, "
                + "which beats most camps."
        case let .addAgility(cut):
            let percent = cut.formatted(.percent.precision(.fractionLength(0)))
            return "Inertial Stabilizers or Nanofiber Internal Structures in your low slots, and Low Friction "
                + "Nozzle Joints rigs, cut align time. You'd need about \(percent) less to reach two seconds."
        case .scoutAhead:
            return "Haulers are a camp's favourite target. Send a scout through first, or check the entry briefs "
                + "and wait out any camp on your route."
        }
    }

    static func footnote(_ check: EscapeCheck) -> String? {
        guard !check.fitKnown else { return nil }
        return "You're in space, so EVE doesn't report your fit. These numbers are for the bare hull with your "
            + "skills. Dock up for figures that include your modules."
    }

    static func symbol(_ verdict: EscapeVerdict) -> String {
        switch verdict {
        case .warpsCloaked: "eye.slash"
        case .hardToCatch: "hare"
        case .catchableByFastLockers: "exclamationmark.triangle"
        case .catchable: "tortoise"
        }
    }

    static func color(_ verdict: EscapeVerdict) -> Color {
        switch verdict {
        case .warpsCloaked, .hardToCatch: .green
        case .catchableByFastLockers: .orange
        case .catchable: .red
        }
    }
}

// MARK:  Card

/// "Can you get away?": how fast the pilot's current ship aligns and warps, whether a gate
/// camp can catch it, and what would help.
struct RouteEscapeCheckCard: View {
    let check: EscapeCheck?
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.sm) {
            Image(systemName: check.map { EscapeCheckText.symbol($0.verdict) } ?? "hare")
                .foregroundStyle(check.map { EscapeCheckText.color($0.verdict) } ?? .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EVESpacing.xs) {
                HStack(spacing: EVESpacing.sm) {
                    Text("Can you get away?").fontWeight(.semibold).foregroundStyle(.primary)
                    if let name = check?.shipName {
                        Text("· \(name)")
                    }
                    Spacer()
                    if isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Button(action: onRefresh) {
                            Image(systemName: "arrow.clockwise").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh escape check")
                        .help("Refresh after switching ships or refitting")
                    }
                }

                if let check {
                    Text(EscapeCheckText.headline(check))
                        .fontWeight(.medium)
                        .foregroundStyle(EscapeCheckText.color(check.verdict))
                    Text(EscapeCheckText.stats(check))
                    Text(EscapeCheckText.explanation(check))
                    ForEach(Array(check.suggestions.enumerated()), id: \.offset) { _, suggestion in
                        Label(EscapeCheckText.suggestion(suggestion), systemImage: "lightbulb")
                            .foregroundStyle(.primary)
                    }
                    if let footnote = EscapeCheckText.footnote(check) {
                        Text(footnote).foregroundStyle(.tertiary)
                    }
                } else if let error {
                    Text(error)
                } else if isLoading {
                    Text("Working out how fast your ship gets into warp…")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
    }
}
