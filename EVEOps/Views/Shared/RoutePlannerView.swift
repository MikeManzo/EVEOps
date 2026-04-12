import SwiftUI

struct RoutePlannerView: View {
    @State private var originInput = ""
    @State private var destinationInput = ""
    @State private var routeFlag = "shortest"
    @State private var route: [RouteSystem] = []
    @State private var isCalculating = false
    @State private var errorMessage: String?

    private var canPlot: Bool {
        !originInput.trimmingCharacters(in: .whitespaces).isEmpty &&
        !destinationInput.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isCalculating
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                inputPanel
                if isCalculating { calculatingView }
                if !route.isEmpty { routePanel }
            }
            .padding()
        }
        .navigationTitle("Route Planner")
    }

    // MARK: - Input Panel

    private var inputPanel: some View {
        GroupBox {
            VStack(spacing: 14) {
                // Origin / Destination row
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Origin", systemImage: "location.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.blue)
                        TextField("e.g. Jita", text: $originInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if canPlot { Task { await plotRoute() } } }
                    }

                    // Swap button
                    Button {
                        swap(&originInput, &destinationInput)
                    } label: {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Destination", systemImage: "mappin.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                        TextField("e.g. Amarr", text: $destinationInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if canPlot { Task { await plotRoute() } } }
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Route Type").font(.caption).foregroundStyle(.secondary)
                        Picker("Route Type", selection: $routeFlag) {
                            Text("Shortest").tag("shortest")
                            Text("Secure (0.5+)").tag("secure")
                            Text("Insecure (<0.5)").tag("insecure")
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 360)
                    }

                    Spacer()

                    Button {
                        Task { await plotRoute() }
                    } label: {
                        Label("Plot Route", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlot)
                }

                if let errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(errorMessage)
                    }
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        } label: {
            Label("Route Planner", systemImage: "map.fill")
        }
    }

    private var calculatingView: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Calculating route…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Route Panel

    private var routePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(originInput) → \(destinationInput)")
                            .font(.headline)
                        Text("\(route.count - 1) jump\(route.count == 2 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    securitySummary
                }
                .padding(.bottom, 12)

                Divider()

                LazyVStack(spacing: 0) {
                    ForEach(Array(route.enumerated()), id: \.offset) { index, system in
                        RouteSystemRow(
                            system: system,
                            jumpNumber: index + 1,
                            isLast: index == route.count - 1,
                            isFirst: index == 0
                        )
                    }
                }
            }
        } label: {
            Label("Route", systemImage: "arrow.triangle.turn.up.right.circle.fill")
        }
    }

    private var securitySummary: some View {
        HStack(spacing: 6) {
            let highSec = route.filter { $0.securityStatus >= 0.5 }.count
            let lowSec = route.filter { $0.securityStatus > 0.0 && $0.securityStatus < 0.5 }.count
            let nullSec = route.filter { $0.securityStatus <= 0.0 }.count
            if highSec > 0 {
                secPill("\(highSec)H", color: .blue)
            }
            if lowSec > 0 {
                secPill("\(lowSec)L", color: .orange)
            }
            if nullSec > 0 {
                secPill("\(nullSec)N", color: .red)
            }
        }
    }

    private func secPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold().monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Route Calculation

    private func plotRoute() async {
        let origin = originInput.trimmingCharacters(in: .whitespaces)
        let destination = destinationInput.trimmingCharacters(in: .whitespaces)
        guard !origin.isEmpty, !destination.isEmpty else { return }

        isCalculating = true
        errorMessage = nil
        route = []

        do {
            // Resolve system names to IDs
            let idsResponse: ESIIDsResponse = try await ESIClient.shared.post(
                "/universe/ids/", body: [origin, destination]
            )
            guard let systems = idsResponse.solarSystems, !systems.isEmpty else {
                throw RoutePlannerError.systemNotFound(name: origin)
            }
            guard let originSystem = systems.first(where: { $0.name.lowercased() == origin.lowercased() }) else {
                throw RoutePlannerError.systemNotFound(name: origin)
            }
            guard let destSystem = systems.first(where: { $0.name.lowercased() == destination.lowercased() }) else {
                throw RoutePlannerError.systemNotFound(name: destination)
            }

            // Fetch route
            let systemIds: [Int] = try await ESIClient.shared.fetch(
                "/route/\(originSystem.id)/\(destSystem.id)/",
                queryItems: [URLQueryItem(name: "flag", value: routeFlag)]
            )

            // Resolve all system details concurrently
            let resolvedSystems = await withTaskGroup(of: (Int, RouteSystem).self) { group -> [RouteSystem] in
                for (index, systemId) in systemIds.enumerated() {
                    group.addTask {
                        let solarSystem = await UniverseCache.shared.solarSystem(id: systemId)
                        return (index, RouteSystem(
                            id: systemId,
                            name: solarSystem?.name ?? "System #\(systemId)",
                            securityStatus: solarSystem?.securityStatus ?? 0.0
                        ))
                    }
                }
                var indexed: [(Int, RouteSystem)] = []
                for await result in group { indexed.append(result) }
                indexed.sort { $0.0 < $1.0 }
                return indexed.map(\.1)
            }
            route = resolvedSystems
        } catch let e as RoutePlannerError {
            errorMessage = e.description
        } catch {
            errorMessage = error.localizedDescription
        }
        isCalculating = false
    }
}

// MARK: - Route Planner Error

enum RoutePlannerError: Error {
    case systemNotFound(name: String)
    case noRoute

    var description: String {
        switch self {
        case .systemNotFound(let name): return "System not found: \"\(name)\". Check the spelling."
        case .noRoute: return "No route found between these systems with the selected route type."
        }
    }
}

// MARK: - Route System Model

struct RouteSystem {
    let id: Int
    let name: String
    let securityStatus: Double

    var displaySecurity: String {
        let clamped = max(0.0, securityStatus)
        return String(format: "%.1f", clamped)
    }

    var securityColor: Color {
        switch securityStatus {
        case 0.9...: return Color(red: 0.3, green: 0.9, blue: 1.0)
        case 0.8..<0.9: return Color(red: 0.0, green: 0.9, blue: 0.8)
        case 0.7..<0.8: return Color(red: 0.0, green: 0.9, blue: 0.4)
        case 0.6..<0.7: return Color(red: 0.4, green: 0.9, blue: 0.0)
        case 0.5..<0.6: return Color(red: 0.9, green: 0.9, blue: 0.0)
        case 0.4..<0.5: return Color(red: 1.0, green: 0.6, blue: 0.0)
        case 0.3..<0.4: return Color(red: 1.0, green: 0.4, blue: 0.0)
        case 0.2..<0.3: return Color(red: 1.0, green: 0.2, blue: 0.0)
        case 0.1..<0.2: return Color(red: 0.9, green: 0.0, blue: 0.0)
        default: return Color(red: 0.6, green: 0.0, blue: 0.0)
        }
    }
}

// MARK: - Route System Row

struct RouteSystemRow: View {
    let system: RouteSystem
    let jumpNumber: Int
    let isLast: Bool
    let isFirst: Bool

    private var accentColor: Color {
        isFirst ? .blue : isLast ? .green : .clear
    }

    var body: some View {
        HStack(spacing: 0) {
            // Vertical connector track
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                Circle()
                    .fill(isFirst ? Color.blue : isLast ? Color.green : system.securityColor)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(isLast ? Color.clear : Color.secondary.opacity(0.25))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 20)
            .padding(.leading, 8)

            HStack(spacing: 10) {
                // Jump number
                Text("\(jumpNumber)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 24, alignment: .trailing)

                // Security badge
                Text(system.displaySecurity)
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(system.securityColor)
                    .frame(width: 30, alignment: .center)
                    .padding(.vertical, 2)
                    .background(system.securityColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))

                // System name
                Text(system.name)
                    .font(.subheadline)
                    .fontWeight(isFirst || isLast ? .semibold : .regular)

                Spacer()

                if isFirst {
                    Text("ORIGIN").font(.caption2.bold()).foregroundStyle(.blue)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                } else if isLast {
                    Text("DEST").font(.caption2.bold()).foregroundStyle(.green)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.green.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 36)
        .background(isFirst ? Color.blue.opacity(0.05) : isLast ? Color.green.opacity(0.05) : Color.clear)
    }
}
