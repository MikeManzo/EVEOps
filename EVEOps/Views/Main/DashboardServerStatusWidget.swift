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
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .foregroundStyle(accent)
                        .font(.callout)
                    Text("Tranquility")
                        .font(.title3.bold())
                    if apiStatus.vipMode {
                        Text("VIP")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow, in: Capsule())
                            .foregroundStyle(.black)
                    }
                    if !healthy {
                        Text(apiStatus.maintenanceInProgress != nil ? "MAINTENANCE" : "DEGRADED")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(accent.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 24) {
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
                        Spacer()
                        populationSparkline
                    }

                    serviceStatusSection
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
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
        HStack(spacing: 6) {
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

            VStack(alignment: .leading, spacing: 8) {
                if !apiStatus.statusDescription.isEmpty {
                    HStack(spacing: 6) {
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
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(apiStatus.degradedRoutes.prefix(6)) { route in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(route.status == "red" ? Color.red : Color.yellow)
                                        .frame(width: 5, height: 5)
                                    Text("\(route.method.uppercased()) \(route.route)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            if apiStatus.degradedRoutes.count > 6 {
                                Text("+\(apiStatus.degradedRoutes.count - 6) more degraded")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.leading, 4)
                    }
                }

                if budgetLow {
                    HStack(spacing: 6) {
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
        Text(text)
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(0.15), in: Capsule())
    }

    @ViewBuilder
    private func incidentRow(_ incident: StatuspageSummary.Incident) -> some View {
        HStack(alignment: .top, spacing: 6) {
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
        HStack(alignment: .top, spacing: 6) {
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
            Chart(samples) { sample in
                LineMark(x: .value("Time", sample.date), y: .value("Players", sample.players))
                    .foregroundStyle(.green)
                AreaMark(x: .value("Time", sample.date), y: .value("Players", sample.players))
                    .foregroundStyle(.green.opacity(0.1))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 220, height: 50)
        } else {
            Text("Gathering trend data\u{2026}")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 220, height: 50)
        }
    }
}
