import SwiftUI

struct CharacterClonesView: View {
    @Environment(AccountManager.self) private var accountManager
    @State private var clonesResponse: ESIClonesResponse?
    @State private var activeImplants: [ResolvedImplant] = []
    @State private var jumpClones: [ResolvedJumpClone] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var selectedImplant: ResolvedImplant?

    var body: some View {
        LoadingStateView(isLoading: isLoading, error: error, isEmpty: clonesResponse == nil) {
            HStack(spacing: 0) {
                List(selection: $selectedImplant) {
                    jumpCooldownSection
                    activeImplantsSection
                    jumpClonesSection
                }
                .frame(maxWidth: .infinity)

                if let implant = selectedImplant {
                    Divider()
                    ImplantDetailView(implant: implant)
                        .frame(width: 320)
                }
            }
        }
        .navigationTitle("Clones")
        .task { await loadClones() }
    }

    private var jumpCooldownSection: some View {
        Section("Jump Clone Cooldown") {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.blue)
                Text("Clone Jump Timer")
                Spacer()
                if let lastJump = clonesResponse?.lastCloneJumpDate {
                    let cooldownEnd = lastJump.addingTimeInterval(36000)
                    if cooldownEnd > Date() {
                        Text(EVEFormatters.timeUntil(cooldownEnd))
                            .foregroundStyle(.orange)
                            .monospacedDigit()
                    } else {
                        Text("Ready")
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Ready")
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var activeImplantsSection: some View {
        Section("Active Implants") {
            if activeImplants.isEmpty {
                Text("No implants installed")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(activeImplants) { implant in
                    HStack {
                        AsyncImage(url: EVEImageURL.typeIcon(implant.typeId, size: 64)) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .frame(width: 28, height: 28)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "brain.head.profile")
                                    .foregroundStyle(.purple)
                                    .frame(width: 28, height: 28)
                            }
                        }
                        Text(implant.name)
                    }
                    .tag(implant)
                }
            }
        }
    }

    private var jumpClonesSection: some View {
        Section("Jump Clones (\(jumpClones.count))") {
            ForEach(jumpClones, id: \.jumpCloneId) { clone in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundStyle(.teal)
                        Text(clone.name ?? "Unnamed Clone")
                            .font(.body)
                    }
                    Text(clone.locationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 28)
                    if !clone.implantNames.isEmpty {
                        Text("Implants: \(clone.implantNames.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 28)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func loadClones() async {
        guard let account = accountManager.selectedAccount else { return }
        isLoading = true
        do {
            let token = try await accountManager.validToken(for: account)
            let clones: ESIClonesResponse = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/clones/", token: token
            )
            clonesResponse = clones

            let implantIDs: [Int] = try await ESIClient.shared.fetch(
                "/characters/\(account.characterID)/implants/", token: token
            )
            // Batch-resolve all implant type names via UniverseCache
            let allImplantIDs = implantIDs + clones.jumpClones.flatMap(\.implants)
            let resolvedTypes = await UniverseCache.shared.types(ids: allImplantIDs)

            var resolved: [ResolvedImplant] = []
            for implantID in implantIDs {
                let name = resolvedTypes[implantID]?.name ?? "Implant #\(implantID)"
                resolved.append(ResolvedImplant(typeId: implantID, name: name))
            }
            activeImplants = resolved
            if selectedImplant == nil { selectedImplant = resolved.first }

            var resolvedClones: [ResolvedJumpClone] = []
            for jc in clones.jumpClones {
                let locName = await NameResolver.shared.resolve(id: jc.locationId)
                let implantNames = jc.implants.prefix(10).map { impID in
                    resolvedTypes[impID]?.name ?? "Implant #\(impID)"
                }
                resolvedClones.append(ResolvedJumpClone(
                    jumpCloneId: jc.jumpCloneId,
                    name: jc.name,
                    locationId: jc.locationId,
                    locationName: locName,
                    implantNames: implantNames
                ))
            }
            jumpClones = resolvedClones
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

struct ResolvedImplant: Identifiable, Hashable {
    let typeId: Int
    let name: String

    var id: Int { typeId }
}

struct ResolvedJumpClone {
    let jumpCloneId: Int
    let name: String?
    let locationId: Int
    let locationName: String
    let implantNames: [String]
}
