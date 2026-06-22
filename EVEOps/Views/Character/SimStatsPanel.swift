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
                    if simState.isLoadingShip || simState.isLoadingSDE {
                        VStack(spacing: 8) {
                            ProgressView()
                            if simState.isLoadingSDE {
                                Text("Syncing EVE SDE data…")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity).padding()
                    } else if simState.stats.hasData {
                        SimCalcInfoBanner()
                        SimFittingSection(stats: simState.stats)
                        SimCapBlock(stats: simState.stats)
                        SimOffenseBlock(stats: simState.stats)
                        SimDefenseBlock(stats: simState.stats)
                        SimTargetingBlock(stats: simState.stats)
                        SimNavBlock(stats: simState.stats)
                        SimDronesBlock(stats: simState.stats)
                        SimImplantsBlock()
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

// MARK:  Calculation info banner

private struct SimCalcInfoBanner: View {
    @Environment(SimulatorState.self) private var simState
    @State private var showingInfo = false

    var body: some View {
        HStack(spacing: 6) {
            Button { showingInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.7))
                Text("Limitations")
            }
            .buttonStyle(.plain)
            .help("How stats are calculated")
            .popover(isPresented: $showingInfo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("How Stats Are Calculated")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("bolt.fill",
                                "Toggle active modules on/off. Active 'ON' shows peak performance with all hardeners cycling — the same baseline used by pyfa and EFT. Active 'OFF' shows the passive-only view closely matching the in-game station display with hardeners idle.")

                        infoRow("shield.lefthalf.filled",
                                "With active modules 'ON', resistance values reflect hardeners cycling. Toggle 'OFF' to see the passive-only resist values that match in-game readings when hardeners are not activated.")

                        infoRow("person.fill",
                                "Character skills are applied at the current trained skill level. Omega skills above your active clone level are excluded.")

                        infoRow("capsule.fill",
                                "Loaded implants are included by default. Toggle them 'OFF' to see the base stats.")
                    }

                    Divider()

                    Text("What's Not Simulated")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("person.2.fill",
                                "Fleet command bursts — warp speed, speed, agility, and other bonuses applied by Command Destroyers or Command Battlecruisers in your fleet.")

                        infoRow("pills.fill",
                                "Combat boosters and drugs — temporary stat bonuses from consumables active at the time of capture.")

                        infoRow("circle.hexagongrid.fill",
                                "Environmental modifiers — wormhole effects, Abyssal filament bonuses/penalties, and similar in-space conditions.")

                        infoRow("bolt.trianglebadge.exclamationmark",
                                "Module scripts and charges — damage control scripts, sensor booster scripts, and loaded charges that alter module behaviour.")

                        infoRow("building.2.fill",
                                "Structure service bonuses — Standup Warp Speed Upgrade and similar Upwell structure modules that apply passive bonuses to docked or tethered ships.")
                    }

                    Text("Powered by EVEShipFit dogma-engine")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .frame(width: 300)
            }

            Spacer()

            Text(simState.activeModulesEnabled ? "Active Mode" : "Passive Mode")
                .font(.system(size: 10))
                .foregroundStyle(.white)

            Toggle(isOn: Binding(
                get: { simState.activeModulesEnabled },
                set: { v in simState.activeModulesEnabled = v; simState.recomputeStats() }
            )) { EmptyView() }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                                       tip: "CPU — remaining processing power (negative = over budget)")
                    }
                    if stats.powerTotal > 0 {
                        SimResourceBar(label: "PG", used: stats.powerUsed, total: stats.powerTotal,
                                       unit: "MW", color: .orange,
                                       tip: "Power Grid — remaining power (negative = over budget)")
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
        // Match in-game convention: show remaining (positive = headroom, negative = over-limit)
        let remaining = total - used
        return "\(fmtSigned(remaining)) / \(fmt(total))\(unit.isEmpty ? "" : " \(unit)")"
    }

    private func fmt(_ v: Double) -> String {
        abs(v) >= 100 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    private func fmtSigned(_ v: Double) -> String {
        let a = abs(v)
        let s = a >= 100 ? String(format: "%.0f", a) : String(format: "%.1f", a)
        return v < 0 ? "-\(s)" : s
    }
}

// MARK:  Capacitor

struct SimCapBlock: View {
    let stats: SimStats

    @AppStorage("sim.section.capacitor.expanded") private var isExpanded = true

    private var peakRecharge: Double {
        guard stats.rechargeRateSec > 0 else { return 0 }
        return 2.5 * stats.capacitorCapacity / stats.rechargeRateSec
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
                        Text("Δ \(net.formatted(.number.precision(.fractionLength(1)))) GJ/s (\((pct / 100).formatted(.percent.precision(.fractionLength(1)))))")
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
        let m = Int(s) / 60
        let sec = s - Double(m * 60)
        return m > 0 ? String(format: "%dm %02.0fs", m, sec) : String(format: "%.2f s", s)
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
            Text((value / 100).formatted(.percent.precision(.fractionLength(1))))
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
    @State private var implantTypes: [Int: ESIType] = [:]

    var body: some View {
        if !simState.implantTypeIds.isEmpty {
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
            .task(id: simState.implantTypeIds.sorted()) {
                let fetched = await UniverseCache.shared.types(ids: simState.implantTypeIds)
                implantTypes = fetched
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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(simState.implantTypeIds.sorted(), id: \.self) { typeId in
                HStack(spacing: 8) {
                    AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 64)) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 3).fill(.quaternary)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(implantTypes[typeId]?.name ?? "Loading…")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(implantTypes[typeId] == nil ? .tertiary : .primary)
                            .lineLimit(1)
                        if let t = implantTypes[typeId], let bonus = primaryBonus(for: t) {
                            Text(bonus)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // Returns a human-readable description of the implant's primary bonus attribute.
    private func primaryBonus(for esiType: ESIType) -> String? {
        guard let attrs = esiType.dogmaAttributes else { return nil }

        // Flat bonuses (integer values like +1 to +5)
        let flatMap: [Int: String] = [
            175: "Charisma",
            176: "Intelligence",
            177: "Memory",
            178: "Perception",
            179: "Willpower",
        ]

        // Percent bonuses — keyed on the implant's own bonus attribute ID (NOT the ship
        // attribute being modified). Confirmed from ESI dogma_attributes for each series.
        // Do NOT include attribute 422 — that is techLevel and appears on every item.
        let pctMap: [Int: String] = [
            // Armor / Hull — Noble Hull Upgrades HG series
            1083: "Armor HP",
            312:  "Armor Repair",       // Noble Repair Systems RS (negative → reduction)
            // Shield — Gnome series
            338:  "Shield Recharge",    // Shield Operation SP (negative → reduction)
            323:  "Shield PG",          // Shield Upgrades SU (negative → PG cost reduction)
            // Navigation — Rogue series
            1076: "Max Velocity",       // Navigation NN
            151:  "Agility",            // Evasive Maneuvering EM (negative → inertia reduction)
            318:  "MWD Speed",          // Acceleration Control AC
            // Warp — Rogue WS series
            624:  "Warp Speed",
            // Capacitor / Power — Squire series
            1079: "Capacitor Capacity", // Capacitor Management EM
            313:  "Power Grid",         // Power Grid Management EG
            // Turret — Lancer series
            317:  "Turret Cap Use",     // Controlled Bursts CB (negative → cap reduction)
            441:  "Gunnery ROF",        // Gunnery RF (negative → cycle time reduction)
            292:  "Turret Damage",      // Large Energy Turret LE
            // Missile — Deadeye series
            20:   "Missile Velocity",   // Missile Projection MP
            293:  "Missile ROF",        // Rapid Launch RL (negative → cycle time reduction)
            847:  "Missile Guidance",   // Target Navigation Prediction TN
        ]

        // Attributes stored as negative but representing a positive player benefit.
        // Negate before display so the UI shows "+3% Agility" instead of "-3% Agility".
        let negatedAttributes: Set<Int> = [151, 293, 312, 317, 323, 338, 441]

        // Check flat attributes first
        for attr in attrs {
            if let label = flatMap[attr.attributeId], attr.value != 0 {
                let v = Int(attr.value.rounded())
                return "\(v >= 0 ? "+" : "")\(v) \(label)"
            }
        }

        // Check percent attributes — skip techLevel (422) which is present on all items
        for attr in attrs where attr.attributeId != 422 {
            if let label = pctMap[attr.attributeId], attr.value != 0 {
                let pct = negatedAttributes.contains(attr.attributeId) ? -attr.value : attr.value
                let sign = pct >= 0 ? "+" : ""
                let pctStr = pct == pct.rounded()
                    ? (pct / 100).formatted(.percent.precision(.fractionLength(0)))
                    : (pct / 100).formatted(.percent.precision(.fractionLength(1)))
                return "\(sign)\(pctStr) \(label)"
            }
        }

        return nil
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
