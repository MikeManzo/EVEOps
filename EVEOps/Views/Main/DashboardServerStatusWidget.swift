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

// MARK:  Server Status Widget

struct ServerStatusWidgetView: View {
    @Binding var isExpanded: Bool
    @Environment(APIStatusMonitor.self) private var apiStatus
    @State private var now = Date()
    @State private var hoveredSampleDate: Date?

    private var timeUntilDowntime: TimeInterval {
        EVEDowntime.next(from: now).timeIntervalSince(now)
    }

    private var uptimeText: String {
        guard let start = apiStatus.serverStartTime else { return "—" }
        return EVEFormatters.formatDuration(max(Int(now.timeIntervalSince(start)), 0))
    }

    private var healthy: Bool { apiStatus.isReachable && !apiStatus.hasServiceIssue }
    private var accent: Color { healthy ? .green : .orange }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: EVESpacing.md) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(accent)
                        .font(.callout)
                        // Keeps pulsing while Tranquility is unreachable, degraded or
                        // in maintenance.
                        .evePulse(isActive: !healthy)
                    Text("Tranquility")
                        .font(.title3.bold())
                    if apiStatus.vipMode {
                        Text("VIP")
                            .font(.caption2.bold())
                            .padding(.horizontal, EVESpacing.sm)
                            .padding(.vertical, EVESpacing.xxs)
                            .background(.yellow, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    if !healthy {
                        Text(apiStatus.maintenanceInProgress != nil ? "MAINTENANCE" : "DEGRADED")
                            .font(.caption2.bold())
                            .padding(.horizontal, EVESpacing.sm).padding(.vertical, EVESpacing.xxs)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    Spacer()
                    if let players = apiStatus.playersOnline {
                        Text("\(players.formatted()) online")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, EVESpacing.lg)
                .padding(.vertical, 10)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: EVERadius.lg))
                .overlay(RoundedRectangle(cornerRadius: EVERadius.lg).strokeBorder(accent.opacity(0.15), lineWidth: 1))
                .eveHoverable(cornerRadius: EVERadius.lg)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: EVESpacing.lg) {
                    HStack(alignment: .top, spacing: EVESpacing.xxl) {
                        VStack(alignment: .leading, spacing: 10) {
                            if apiStatus.isReachable {
                                metricRow(label: "Uptime", value: uptimeText)
                                metricRow(label: "Next downtime", value: "in \(EVEFormatters.formatDuration(max(Int(timeUntilDowntime), 0)))")
                            } else {
                                metricRow(label: "Status", value: apiStatus.statusMessage.isEmpty ? "Downtime in progress" : apiStatus.statusMessage)
                            }
                            if let version = apiStatus.serverVersion {
                                metricRow(label: "Build", value: version)
                            }
                        }
                        .fixedSize()

                        // #: Sparkline fills the remaining panel width instead of sitting in a
                        // fixed-size box, so the population trend actually reads over its full span.
                        populationSparkline
                    }

                    serviceStatusSection
                }
                .padding(.horizontal, EVESpacing.lg)
                .padding(.top, EVESpacing.lg)
                .padding(.bottom, EVESpacing.xs)
            }
        }
        .task(id: "server-status-timer") {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack(spacing: EVESpacing.sm) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    // MARK: Service status (status.eveonline.com + ESI route health)

    @ViewBuilder
    private var serviceStatusSection: some View {
        let routeTotal = apiStatus.esiRoutesGreen + apiStatus.esiRoutesYellow + apiStatus.esiRoutesRed
        let budgetLow = apiStatus.esiErrorBudgetRemain < 30 && apiStatus.esiErrorBudgetResetAt > now

        if routeTotal > 0 || !apiStatus.activeIncidents.isEmpty || !apiStatus.maintenance.isEmpty || budgetLow {
            Divider()

            VStack(alignment: .leading, spacing: EVESpacing.md) {
                if !apiStatus.statusDescription.isEmpty {
                    HStack(spacing: EVESpacing.sm) {
                        Circle()
                            .fill(indicatorColor(apiStatus.statusIndicator))
                            .frame(width: 7, height: 7)
                        Text(apiStatus.statusDescription)
                            .font(.caption)
                        Spacer()
                        if let link = URL(string: "https://status.eveonline.com") {
                            Link("status.eveonline.com", destination: link)
                                .font(.caption2)
                        }
                    }
                }

                ForEach(apiStatus.activeIncidents) { incident in
                    incidentRow(incident)
                }

                ForEach(apiStatus.maintenance) { m in
                    maintenanceRow(m)
                }

                if routeTotal > 0 {
                    HStack(spacing: 10) {
                        Text("ESI routes")
                            .font(.caption).foregroundStyle(.secondary)
                        routePill("\(apiStatus.esiRoutesGreen)", .green)
                        if apiStatus.esiRoutesYellow > 0 { routePill("\(apiStatus.esiRoutesYellow)", .yellow) }
                        if apiStatus.esiRoutesRed > 0 { routePill("\(apiStatus.esiRoutesRed)", .red) }
                        Spacer()
                    }

                    if !apiStatus.degradedRoutes.isEmpty {
                        VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                            ForEach(apiStatus.degradedRoutes.prefix(6)) { route in
                                HStack(spacing: EVESpacing.sm) {
                                    Circle()
                                        .fill(route.status == "red" ? Color.red : Color.yellow)
                                        .frame(width: 5, height: 5)
                                    Text("\(route.method.uppercased()) \(route.route)")
                                        .font(.eveCode)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            if apiStatus.degradedRoutes.count > 6 {
                                Text("+\(apiStatus.degradedRoutes.count - 6) more degraded")
                                    .font(.eveLabel)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.leading, EVESpacing.xs)
                    }
                }

                if budgetLow {
                    HStack(spacing: EVESpacing.sm) {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .font(.caption2).foregroundStyle(.orange)
                        Text("ESI error budget: \(apiStatus.esiErrorBudgetRemain) left — resets \(apiStatus.esiErrorBudgetResetAt, format: .relative(presentation: .named))")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func indicatorColor(_ indicator: String) -> Color {
        switch indicator {
        case "none":     return .green
        case "minor":    return .yellow
        case "major":    return .orange
        case "critical": return .red
        default:         return .secondary
        }
    }

    private func routePill(_ text: String, _ color: Color) -> some View {
        EVEChip(Text(text), tint: color, size: .small, monospacedDigits: true)
    }

    @ViewBuilder
    private func incidentRow(_ incident: StatuspageSummary.Incident) -> some View {
        HStack(alignment: .top, spacing: EVESpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(incident.impact == "critical" ? .red : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(incident.name).font(.caption.weight(.medium))
                if let body = incident.latestUpdate {
                    Text(body)
                        .font(.caption2).foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let s = incident.shortlink, let url = URL(string: s) {
                Link("details", destination: url).font(.caption2)
            }
        }
    }

    @ViewBuilder
    private func maintenanceRow(_ m: StatuspageSummary.Maintenance) -> some View {
        let inProgress = m.status == "in_progress" || m.status == "verifying"
        HStack(alignment: .top, spacing: EVESpacing.sm) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.caption2)
                .foregroundStyle(inProgress ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.caption.weight(.medium))
                if inProgress, let until = m.scheduledUntil {
                    Text("In progress — ends \(until, format: .relative(presentation: .named))")
                        .font(.caption2).foregroundStyle(.orange)
                } else if let start = m.scheduledFor {
                    Text("Scheduled \(start, format: .relative(presentation: .named))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var populationSparkline: some View {
        let samples = apiStatus.populationHistory
        if samples.count > 1 {
            let hovered = hoveredSampleDate.flatMap { date in
                samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
            }
            Chart {
                ForEach(samples) { sample in
                    AreaMark(x: .value("Time", sample.date), y: .value("Players", sample.players))
                        .foregroundStyle(.eveAreaFill(.green))
                        .interpolationMethod(EVEChartStyle.interpolation)
                    LineMark(x: .value("Time", sample.date), y: .value("Players", sample.players))
                        .foregroundStyle(.green)
                        .lineStyle(EVEChartStyle.line)
                        .interpolationMethod(EVEChartStyle.interpolation)
                }
                if let hovered {
                    RuleMark(x: .value("Time", hovered.date))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(EVEChartStyle.reference)
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            EVEChartCallout(
                                title: hovered.date.formatted(date: .omitted, time: .shortened),
                                value: String(localized: "\(hovered.players.formatted()) online"),
                                tint: .green
                            )
                        }
                    PointMark(x: .value("Time", hovered.date), y: .value("Players", hovered.players))
                        .foregroundStyle(.green)
                        .symbolSize(EVEChartStyle.hoverSymbolSize)
                }
            }
            .chartXSelection(value: $hoveredSampleDate)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .eveChartAccessibility(String(localized: "Players online"),
                                   points: samples.map { ($0.date, Double($0.players)) },
                                   format: { Int($0).formatted() })
            .frame(maxWidth: .infinity)
            .frame(height: 60)
        } else {
            Text("Gathering trend data\u{2026}")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
        }
    }
}
