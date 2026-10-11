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

/// Turns a `TripStake` into plain-language lines. Kept apart from the view so the wording
/// reads in one place.
enum TripStakeText {
    static func isk(_ value: Double) -> String { EVEFormatters.formatISKShort(value) }

    /// What losing the ship costs, with the breakdown.
    static func shipLine(_ stake: TripStake) -> String {
        let ship = stake.shipTypeName ?? "ship"
        guard stake.contentsKnown else {
            return "If your \(ship) is destroyed you lose at least \(isk(stake.hull)) for the hull. "
                + "You're in space, so EVE doesn't report your fit or cargo. Dock up for the full figure."
        }
        var parts = ["hull \(isk(stake.hull))", "fit \(isk(stake.fit))"]
        if stake.cargo > 0 { parts.append("cargo \(isk(stake.cargo))") }
        return "If your \(ship) is destroyed you lose about \(isk(stake.shipLoss)): "
            + parts.formatted(.list(type: .and)) + "."
    }

    static func implantLine(_ stake: TripStake) -> String {
        guard stake.implantsKnown else {
            return "Couldn't read your implants. Re-add your character to grant the clones permission."
        }
        if stake.implantCount == 0 {
            return "Your clone has no implants, so losing your pod costs you nothing extra."
        }
        let count = stake.implantCount == 1 ? "your implant" : "your \(stake.implantCount) implants"
        return "If your pod is destroyed too, \(count) (\(isk(stake.implants))) go with it."
    }

    /// Nil when there are no insurance prices for this hull.
    static func insuranceLine(_ stake: TripStake) -> String? {
        guard let payout = stake.platinumPayout, let net = stake.shipLossIfInsured else { return nil }
        return "Insurance only pays for the hull. Platinum would pay back about \(isk(payout)), "
            + "so losing the ship would cost about \(isk(net)). EVEOps can't tell whether this ship is insured."
    }

    static func cloneLine(_ stake: TripStake) -> String? {
        switch stake.cloneAdvice {
        case .jumpToEmptyClone:
            let place = stake.cloneLocationName.map { " in \($0)" } ?? ""
            return "Your implants are worth \(isk(stake.implants)). You have an implant-free jump clone\(place). "
                + "Jumping into it before you undock leaves them safe at home."
        case .noEmptyClone:
            return "Your implants are worth \(isk(stake.implants)) and you have no implant-free jump clone, "
                + "so they travel with you. An empty clone for risky trips keeps them out of harm's way."
        case nil:
            return nil
        }
    }

    static func footnote(_ stake: TripStake) -> String {
        var line = "Jita sell prices."
        if stake.unpricedCount > 0 {
            line += " \(stake.unpricedCount) item\(stake.unpricedCount == 1 ? " has" : "s have") no price and \(stake.unpricedCount == 1 ? "isn't" : "aren't") counted."
        }
        return line
    }
}

// MARK:  Card

/// "What's at stake": the ship, fit, cargo and implants the pilot would risk on this route,
/// what insurance gives back, and whether to leave the implants at home.
struct RouteTripStakeCard: View {
    let stake: TripStake?
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EVESpacing.sm) {
            Image(systemName: "scalemass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: EVESpacing.xs) {
                HStack(spacing: EVESpacing.sm) {
                    Text("What's at stake").fontWeight(.semibold).foregroundStyle(.primary)
                    if let name = stake?.shipName {
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
                        .accessibilityLabel("Refresh estimate")
                        .help("Refresh after switching ships or changing your cargo")
                    }
                }

                if let stake {
                    Text(TripStakeText.shipLine(stake))
                    Text(TripStakeText.implantLine(stake))
                    if let insurance = TripStakeText.insuranceLine(stake) {
                        Text(insurance)
                    }
                    if let clone = TripStakeText.cloneLine(stake) {
                        cloneAdvice(clone, stake: stake)
                    }
                    Text(TripStakeText.footnote(stake))
                        .foregroundStyle(.tertiary)
                } else if let error {
                    Text(error)
                } else if isLoading {
                    Text("Adding up your ship, cargo and implants…")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.bottom, 10)
    }

    private func cloneAdvice(_ text: String, stake: TripStake) -> some View {
        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
            Label(text, systemImage: "person.2.badge.gearshape")
                .foregroundStyle(.primary)
            if case let .jumpToEmptyClone(_, readyAt?) = stake.cloneAdvice {
                Text("Your next clone jump is available \(readyAt, format: .relative(presentation: .named)).")
            }
            Button {
                AppRouter.shared.pendingSection = .clones
            } label: {
                Label("Open Clones", systemImage: "arrow.right.circle")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        }
        .padding(EVESpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: EVERadius.md))
    }
}
