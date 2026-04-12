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
                if !route.isEmpty { routePanel }
            }
            .padding()
        }
        .navigationTitle("Route Planner")
    }

    // MARK: - Input Panel

    private var inputPanel: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Origin").font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. Jita", text: $originInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if canPlot { Task { await plotRoute() } } }
                    }

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination").font(.caption).foregroundStyle(.secondary)
                        TextField("e.g. Amarr", text: $destinationInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { if canPlot { Task { await plotRoute() } } }
                    }
                }

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
                        Label(isCalculating ? "Calculating…" : "Plot Route", systemImage: "map.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canPlot)
                    .padding(.top, 16)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } label: {
            Label("Route Planner", systemImage: "map.fill")
        }
    }

    // MARK: - Route Panel

    private var routePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(route.count - 1) jump\(route.count == 2 ? "" : "s")")
                        .font(.headline)
                    Spacer()
                    securitySummary
                }
                .padding(.bottom, 8)

                Divider()

                LazyVStack(spacing: 0) {
                    ForEach(Array(route.enumerated()), id: \.offset) { index, system in
                        RouteSystemRow(system: system, jumpNumber: index + 1, isLast: index == route.count - 1)
                        if index < route.count - 1 {
                            Divider().padding(.leading, 80)
                        }
                    }
                }
            }
        } label: {
            Label("Route: \(originInput) → \(destinationInput)", systemImage: "arrow.triangle.turn.up.right.circle.fill")
        }
    }

    private var securitySummary: some View {
        HStack(spacing: 6) {
            let highSec = route.filter { $0.securityStatus >= 0.5 }.count
            let lowSec = route.filter { $0.securityStatus > 0.0 && $0.securityStatus < 0.5 }.count
            let nullSec = route.filter { $0.securityStatus <= 0.0 }.count
            if highSec > 0 {
                Label("\(highSec) high", systemImage: "shield.fill").foregroundStyle(.blue).font(.caption)
            }
            if lowSec > 0 {
                Label("\(lowSec) low", systemImage: "shield.lefthalf.filled").foregroundStyle(.orange).font(.caption)
            }
            if nullSec > 0 {
                Label("\(nullSec) null", systemImage: "shield.slash.fill").foregroundStyle(.red).font(.caption)
            }
        }
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

    var body: some View {
        HStack(spacing: 10) {
            Text("\(jumpNumber)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)

            Text(system.displaySecurity)
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(system.securityColor)
                .frame(width: 28, alignment: .center)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(system.securityColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

            Text(system.name)
                .font(.subheadline)

            Spacer()

            if jumpNumber == 1 {
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
        .padding(.vertical, 7)
        .background(jumpNumber == 1 ? Color.blue.opacity(0.05) : isLast ? Color.green.opacity(0.05) : Color.clear)
    }
}
