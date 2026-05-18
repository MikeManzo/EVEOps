//
// SimStatsPanel.swift
// EVEOps
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

// MARK:  Stats Panel

struct SimStatsPanel: View {
    @Environment(SimulatorState.self) private var simState

    var body: some View {
        if simState.shipTypeId == nil {
            VStack(spacing: 14) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 40)).foregroundStyle(.tertiary)
                Text("Ship stats will appear here\nonce a ship is selected")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if simState.isLoadingShip {
                        HStack { Spacer(); ProgressView(); Spacer() }.padding()
                    } else if simState.stats.hasData {
                        SimFittingSection(stats: simState.stats)
                        SimCapBlock(stats: simState.stats)
                        SimOffenseBlock(stats: simState.stats)
                        SimDefenseBlock(stats: simState.stats)
                        SimTargetingBlock(stats: simState.stats)
                        SimNavBlock(stats: simState.stats)
                        SimDronesBlock(stats: simState.stats)
                        SimImplantsBlock()
                        SimTrainingBlock()

                        if simState.isComputingEffects {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.65)
                                Text("Computing module bonuses…")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                            Text("No stat data available for this ship type.")
                                .font(.caption).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding()
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }
}

// MARK:  Section header

private struct SimSectionHeader: View {
    let title: String
    var summary: String? = nil
    var summaryColor: Color = .primary
    var summaryTip: String = ""
    var isExpanded: Binding<Bool>? = nil

    var body: some View {
        Group {
            if let expanded = isExpanded {
                Button { withAnimation(.easeInOut(duration: 0.15)) { expanded.wrappedValue.toggle() } } label: { headerContent }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
            } else {
                headerContent
            }
        }
    }

    private var headerContent: some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let s = summary {
                Text(s)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(summaryColor)
                    .help(summaryTip)
            }
            if let expanded = isExpanded {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }
}

// MARK:  Fitting Resources

struct SimFittingSection: View {
    let stats: SimStats

    @AppStorage("sim.section.fitting.expanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Fitting", isExpanded: $isExpanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    if stats.cpuTotal > 0 {
                        SimResourceBar(label: "CPU", used: stats.cpuUsed, total: stats.cpuTotal,
                                       unit: "tf", color: .teal,
                                       tip: "CPU — processing power consumed by fitted modules (tf)")
                    }
                    if stats.powerTotal > 0 {
                        SimResourceBar(label: "PG", used: stats.powerUsed, total: stats.powerTotal,
                                       unit: "MW", color: .orange,
                                       tip: "Power Grid — power consumed by fitted modules (MW)")
                    }
                    if stats.calibrationTotal > 0 {
                        SimResourceBar(label: "Cal", used: stats.calibrationUsed, total: stats.calibrationTotal,
                                       unit: "", color: .purple,
                                       tip: "Calibration — rig calibration points consumed by fitted rigs")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }
}

private struct SimResourceBar: View {
    let label: String
    let used: Double
    let total: Double
    let unit: String
    let color: Color
    var tip: String = ""

    private var fraction: Double { total > 0 ? min(1.0, used / total) : 0 }
    private var isOver: Bool { used > total }
    private var barColor: Color { isOver ? .red : fraction > 0.85 ? .yellow : color }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
                .help(tip)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(.quaternary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.85))
                        .frame(width: max(0, geo.size.width * CGFloat(fraction)))
                }
            }
            .frame(height: 5)

            Text(formatUsage())
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(isOver ? .red : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func formatUsage() -> String {
        "\(fmt(used)) / \(fmt(total))\(unit.isEmpty ? "" : " \(unit)")"
    }

    private func fmt(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }
}

// MARK:  Capacitor

struct SimCapBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.capacitor.expanded") private var isExpanded = true

    private var peakRecharge: Double {
        guard stats.rechargeRateSec > 0 else { return 0 }
        return 2.5 * 0.25 * stats.capacitorCapacity / stats.rechargeRateSec
    }

    private var capSummary: String {
        guard stats.isCapStable else {
            // Conservative lower-bound: ignores passive regen offsetting drain.
            // Real depletion time is longer — EVE's cap formula is non-linear.
            let secs = stats.capacitorCapacity / stats.capDrainPerSec
            let m = Int(secs) / 60
            let s = Int(secs) % 60
            return m > 0 ? String(format: "~%dm %02ds", m, s) : String(format: "~%.0fs", secs)
        }
        return "Stable"
    }
    private var capColor: Color { stats.isCapStable ? .green : .orange }

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Capacitor", summary: capSummary, summaryColor: capColor, isExpanded: $isExpanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    if stats.capacitorCapacity > 0 {
                        HStack(spacing: 6) {
                            Text(String(format: "%.1f GJ", stats.capacitorCapacity))
                                .font(.system(size: 11).monospacedDigit())
                                .help("Capacitor capacity — total energy the capacitor can hold")
                            if stats.rechargeRateSec > 0 {
                                Text("/")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Text(fmtTime(stats.rechargeRateSec))
                                    .font(.system(size: 11).monospacedDigit())
                                    .help("Capacitor recharge time — time to fully recharge from empty")
                            }
                            Spacer()
                        }
                    }
                    if peakRecharge > 0 {
                        let net = stats.netCapGJps
                        let pct = net / peakRecharge * 100
                        Text(String(format: "Δ %.1f GJ/s (%.1f%%)", net, pct))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(stats.isCapStable ? Color.secondary : Color.orange)
                            .help(stats.isCapStable
                                  ? "Net capacitor recharge at 25% charge level"
                                  : "Net cap drain (passive recharge minus active module cost)")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private func fmtTime(_ s: Double) -> String {
        String(format: "%.2f s", s)
    }
}

// MARK:  Offense

struct SimOffenseBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.offense.expanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Offense", summary: "—", isExpanded: $isExpanded)
            if isExpanded {
                Text("DPS calculation requires ammo selection")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }
}

// MARK:  Defense

struct SimDefenseBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.defense.expanded") private var isExpanded = true

    private var peakShieldRegen: Double {
        guard stats.shieldRechargeTimeSec > 0 else { return 0 }
        return 2.5 * 0.25 * stats.shieldHP / stats.shieldRechargeTimeSec
    }

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Defense", summary: fmtEHP(stats.ehp.minimum),
                             summaryTip: "Worst-case EHP — minimum across EM / Thermal / Kinetic / Explosive",
                             isExpanded: $isExpanded)
            if isExpanded {
                VStack(spacing: 2) {
                    if peakShieldRegen > 0 {
                        SimShieldRechargeRow(peakHPS: peakShieldRegen)
                    }
                    SimHPLayerRow(icon: "shield.lefthalf.filled",
                                  hp: stats.shieldHP, color: .cyan,
                                  resists: stats.shieldResists, layerName: "Shield")
                    SimHPLayerRow(icon: "shield.fill",
                                  hp: stats.armorHP, color: .yellow,
                                  resists: stats.armorResists, layerName: "Armor")
                    SimHPLayerRow(icon: "cube.fill",
                                  hp: stats.hullHP,
                                  color: Color(red: 0.85, green: 0.45, blue: 0.25),
                                  resists: stats.hullResists, layerName: "Hull")
                    if stats.ehp.hasData {
                        SimEHPRow(ehp: stats.ehp)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func fmtEHP(_ v: Double) -> String {
        v >= 1_000_000 ? String(format: "%.2fM ehp", v / 1_000_000) :
        v >= 1_000     ? String(format: "%.0fk ehp", v / 1_000) :
                         String(format: "%.0f ehp", v)
    }
}

private struct SimShieldRechargeRow: View {
    let peakHPS: Double

    private static let emColor        = Color(red: 0.45, green: 0.60, blue: 1.00)
    private static let thermalColor   = Color(red: 1.00, green: 0.40, blue: 0.10)
    private static let kineticColor   = Color(white: 0.65)
    private static let explosiveColor = Color(red: 1.00, green: 0.82, blue: 0.15)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10))
                .foregroundStyle(.cyan)
                .frame(width: 14)
                .help("Passive shield recharge")
            Text(String(format: "%.1f hp/s", peakHPS))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 44, alignment: .leading)
                .help("Peak passive shield recharge rate at 25% shield level")
            Spacer()
            HStack(spacing: 3) {
                damageIcon("bolt.fill",  Self.emColor,        tip: "EM damage type")
                damageIcon("flame.fill", Self.thermalColor,   tip: "Thermal damage type")
                damageIcon("scope",      Self.kineticColor,   tip: "Kinetic damage type")
                damageIcon("burst.fill", Self.explosiveColor, tip: "Explosive damage type")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func damageIcon(_ name: String, _ color: Color, tip: String = "") -> some View {
        Image(systemName: name)
            .font(.system(size: 9))
            .foregroundStyle(color)
            .frame(width: 36)
            .help(tip)
    }
}

private struct SimHPLayerRow: View {
    let icon: String
    let hp: Double
    let color: Color
    let resists: SimResists
    var layerName: String = ""

    private static let emColor        = Color(red: 0.45, green: 0.60, blue: 1.00)
    private static let thermalColor   = Color(red: 1.00, green: 0.40, blue: 0.10)
    private static let kineticColor   = Color(white: 0.65)
    private static let explosiveColor = Color(red: 1.00, green: 0.82, blue: 0.15)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 14)
                .help(layerName.isEmpty ? "" : "\(layerName) layer")
            Text(fmtHP(hp))
                .font(.system(size: 11).monospacedDigit())
                .frame(minWidth: 44, alignment: .leading)
                .help(layerName.isEmpty ? "" : "\(layerName) hit points")
            Spacer()
            HStack(spacing: 3) {
                SimResistBadge(value: resists.em,        color: Self.emColor,
                               tip: layerName.isEmpty ? "" : "\(layerName) EM resistance")
                SimResistBadge(value: resists.thermal,   color: Self.thermalColor,
                               tip: layerName.isEmpty ? "" : "\(layerName) Thermal resistance")
                SimResistBadge(value: resists.kinetic,   color: Self.kineticColor,
                               tip: layerName.isEmpty ? "" : "\(layerName) Kinetic resistance")
                SimResistBadge(value: resists.explosive, color: Self.explosiveColor,
                               tip: layerName.isEmpty ? "" : "\(layerName) Explosive resistance")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }

    private func fmtHP(_ v: Double) -> String {
        "\(Int(v.rounded()).formatted(.number)) hp"
    }
}

// MARK:  Per-type EHP row

private struct SimEHPRow: View {
    let ehp: SimEHPProfile

    private static let emColor        = Color(red: 0.45, green: 0.60, blue: 1.00)
    private static let thermalColor   = Color(red: 1.00, green: 0.40, blue: 0.10)
    private static let kineticColor   = Color(white: 0.65)
    private static let explosiveColor = Color(red: 1.00, green: 0.82, blue: 0.15)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .help("Effective hit points by damage type (all layers combined)")
            Text("ehp")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .leading)
            Spacer()
            HStack(spacing: 3) {
                SimEHPBadge(value: ehp.em,        color: Self.emColor,        tip: "EM EHP — total HP / EM resonance across all layers")
                SimEHPBadge(value: ehp.thermal,   color: Self.thermalColor,   tip: "Thermal EHP")
                SimEHPBadge(value: ehp.kinetic,   color: Self.kineticColor,   tip: "Kinetic EHP")
                SimEHPBadge(value: ehp.explosive, color: Self.explosiveColor, tip: "Explosive EHP")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

private struct SimEHPBadge: View {
    let value: Double
    let color: Color
    var tip: String = ""

    var body: some View {
        Text(fmt(value))
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .frame(width: 36)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
            .help(tip)
    }

    private func fmt(_ v: Double) -> String {
        v >= 1_000_000 ? String(format: "%.1fM", v / 1_000_000) :
        v >= 1_000     ? String(format: "%.0fk", v / 1_000) :
                         String(format: "%.0f", v)
    }
}

private struct SimResistBadge: View {
    let value: Double
    let color: Color
    var tip: String = ""

    private let blockWidth: CGFloat = 36

    var body: some View {
        let fraction = min(max(value / 100.0, 0), 1)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.15))
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.6))
                .frame(width: blockWidth * fraction)
            Text(String(format: "%.1f%%", value))
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
        }
        .frame(width: blockWidth)
        .padding(.vertical, 2)
        .help(tip)
    }
}

// MARK:  Targeting

struct SimTargetingBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.targeting.expanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Targeting",
                             summary: stats.maxTargetRange > 0 ? fmtRange(stats.maxTargetRange) : "—",
                             summaryTip: "Maximum targeting range",
                             isExpanded: $isExpanded)
            if isExpanded {
                VStack(spacing: 3) {
                    simTwoColRow(
                        left:    stats.sensorStrength > 0 ? String(format: "%.2f points", stats.sensorStrength) : "—",
                        leftTip: "Sensor strength — resistance to electronic warfare jamming",
                        right:    stats.scanResolution > 0 ? String(format: "%.0f mm", stats.scanResolution) : "—",
                        rightTip: "Scan resolution — determines how quickly you can lock on to a target"
                    )
                    simTwoColRow(
                        left:    stats.signatureRadius > 0  ? String(format: "%.0f m", stats.signatureRadius)  : "—",
                        leftTip: "Signature radius — how easy this ship is to target and hit by others",
                        right:    stats.maxLockedTargets > 0 ? String(format: "%.0fx", stats.maxLockedTargets) : "—",
                        rightTip: "Maximum number of simultaneously locked targets"
                    )
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }

    private func fmtRange(_ m: Double) -> String {
        m >= 1_000_000 ? String(format: "%.0f Mm", m / 1_000_000) :
        m >= 1_000     ? String(format: "%.2f km", m / 1_000) :
                         String(format: "%.0f m", m)
    }
}

// MARK:  Navigation

struct SimNavBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.navigation.expanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Navigation",
                             summary: stats.maxVelocity > 0 ? String(format: "%.1f m/s", stats.maxVelocity) : "—",
                             summaryTip: "Maximum subwarp velocity",
                             isExpanded: $isExpanded)
            if isExpanded {
                VStack(spacing: 3) {
                    simTwoColRow(
                        left:    stats.mass > 0       ? String(format: "%.2f t", stats.mass / 1_000) : "—",
                        leftTip: "Ship mass — affects inertia and agility",
                        right:    stats.inertiaMod > 0 ? String(format: "%.4fx", stats.inertiaMod)   : "—",
                        rightTip: "Inertia modifier — lower values mean more agile"
                    )
                    simTwoColRow(
                        left:    stats.warpSpeed > 0 ? String(format: "%.2f AU/s", stats.warpSpeed) : "—",
                        leftTip: "Maximum warp speed",
                        right:    stats.alignTime > 0 ? String(format: "%.2f s", stats.alignTime)   : "—",
                        rightTip: "Time to align and enter warp"
                    )
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }
}

// MARK:  Drones

struct SimDronesBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.drones.expanded") private var isExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            SimSectionHeader(title: "Drones", summary: "—", isExpanded: $isExpanded)
            if isExpanded {
                VStack(alignment: .leading, spacing: 3) {
                    if stats.droneBandwidth > 0 {
                        simTwoColRow(
                            left: String(format: "0 / %.0f Mbit/sec", stats.droneBandwidth),
                            leftTip: "Drone bandwidth used / available",
                            right: stats.droneBayCapacity > 0
                                ? String(format: "%.0f m³ bay", stats.droneBayCapacity)
                                : "—",
                            rightTip: "Drone bay capacity"
                        )
                    } else {
                        simTwoColRow(left: "—", right: "—")
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
        }
    }
}

// MARK:  Implants

private struct SimImplantsBlock: View {
    @Environment(SimulatorState.self) private var simState
    @AppStorage("sim.section.implants.expanded") private var isExpanded = true

    var body: some View {
        if !simState.implantTypes.isEmpty {
            VStack(spacing: 0) {
                implantHeader
                if isExpanded {
                    if simState.includeImplants {
                        implantContent
                    } else {
                        Text("Excluded from simulation")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private var implantHeader: some View {
        HStack {
            Text("Implants")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: Binding(
                get: { simState.includeImplants },
                set: { v in simState.includeImplants = v; simState.recomputeStats() }
            )) { EmptyView() }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }

    @ViewBuilder
    private var implantContent: some View {
        let contributions = simState.stats.implantContributions
        if contributions.isEmpty {
            Text("No active implants modify this ship's stats")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(contributions) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            AsyncImage(url: EVEImageURL.typeIcon(c.typeId, size: 64)) { img in
                                img.resizable().aspectRatio(contentMode: .fit)
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                            }
                            .frame(width: 20, height: 20)
                            .clipShape(RoundedRectangle(cornerRadius: 3))

                            Text(c.name)
                                .font(.system(size: 10, weight: .semibold))
                                .lineLimit(1)
                        }
                        ForEach(c.bonuses, id: \.self) { bonus in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(.purple.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                Text(bonus)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 26)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
}

// MARK:  Training

private struct SimTrainingBlock: View {
    @Environment(SimulatorState.self) private var simState
    @AppStorage("sim.section.training.expanded") private var isExpanded = true

    var body: some View {
        let contributions = simState.stats.trainingContributions
        if !contributions.isEmpty {
            VStack(spacing: 0) {
                trainingHeader
                if isExpanded {
                    trainingContent
                }
            }
        }
    }

    private var trainingHeader: some View {
        HStack {
            Text("Training")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(simState.stats.trainingContributions.count) skills")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 14)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.06))
    }

    private var trainingContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(simState.stats.trainingContributions) { c in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        AsyncImage(url: EVEImageURL.typeIcon(c.typeId, size: 64)) { img in
                            img.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                        }
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                        Text("\(c.name) (L\(c.level))")
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    ForEach(c.bonuses, id: \.self) { bonus in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.blue.opacity(0.5))
                                .frame(width: 4, height: 4)
                            Text(bonus)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 26)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

// MARK:  Stat row helpers

@ViewBuilder
private func simTwoColRow(left: String, leftTip: String = "", right: String, rightTip: String = "") -> some View {
    HStack(spacing: 0) {
        Text(left)
            .font(.system(size: 11).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(leftTip)
        Text(right)
            .font(.system(size: 11).monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(rightTip)
    }
}

@ViewBuilder
private func simStatRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).font(.caption2).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.caption2.monospacedDigit())
    }
}
