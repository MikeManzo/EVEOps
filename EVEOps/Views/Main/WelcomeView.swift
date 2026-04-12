import SwiftUI

struct WelcomeView: View {
    @Environment(AccountManager.self) private var accountManager

    // Iconic EVE ship type IDs for the background showcase
    private let showcaseShips: [(typeId: Int, name: String)] = [
        (11567, "Avatar"),
        (23913, "Nyx"),
        (3764, "Leviathan"),
        (671, "Erebus"),
        (42241, "Komodo"),
        (42126, "Vanquisher"),
        (645, "Dominix"),
        (17726, "Apocalypse Navy Issue"),
        (638, "Raven"),
        (641, "Megathron"),
        (24690, "Drake"),
        (587, "Rifter"),
        (17703, "Tempest Fleet Issue"),
        (17636, "Raven Navy Issue"),
        (621, "Caracal"),
        (627, "Thorax"),
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
    ]

    var body: some View {
        ZStack {
            shipBackdrop
            Color.black.opacity(0.55)
            welcomeContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var shipBackdrop: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(showcaseShips, id: \.typeId) { ship in
                AsyncImage(url: URL(string: "https://images.evetech.net/types/\(ship.typeId)/render?size=256")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    case .failure:
                        Rectangle()
                            .fill(Color(white: 0.08))
                            .aspectRatio(1, contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color(white: 0.05))
                            .aspectRatio(1, contentMode: .fill)
                            .overlay(ProgressView().scaleEffect(0.5))
                    }
                }
                .clipped()
            }
        }
        .opacity(0.6)
    }

    private var welcomeContent: some View {
        VStack(spacing: 28) {
            // EVE Logo from the image server (Caldari State logo as a thematic stand-in)
            AsyncImage(url: URL(string: "https://images.evetech.net/corporations/1000125/logo?size=128")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .frame(width: 80, height: 80)
                default:
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 10)

            VStack(spacing: 8) {
                Text("EVEOps")
                    .font(.system(size: 42, weight: .bold, design: .default))
                    .foregroundStyle(.white)

                Text("Command Center for New Eden")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text("Manage all your characters and corporations.\nTrack assets, skills, industry, contracts, and more.")
                .font(.body)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(spacing: 12) {
                Button {
                    Task { await accountManager.addAccount() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                        Text("Log In with EVE Online")
                    }
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .disabled(accountManager.isLoading)

                if accountManager.isLoading {
                    ProgressView("Authenticating with EVE SSO...")
                        .foregroundStyle(.white.opacity(0.7))
                }

                if let error = accountManager.error {
                    Text(error)
                        .foregroundStyle(.red.opacity(0.9))
                        .font(.caption)
                        .padding(.horizontal)
                }
            }

            // Faction logos row
            HStack(spacing: 24) {
                factionLogo(corporationId: 1000125, name: "CONCORD")
                factionLogo(corporationId: 1000066, name: "Caldari")
                factionLogo(corporationId: 1000126, name: "Gallente")
                factionLogo(corporationId: 1000084, name: "Amarr")
                factionLogo(corporationId: 1000127, name: "Minmatar")
            }
            .padding(.top, 8)
        }
        .padding(40)
    }

    private func factionLogo(corporationId: Int, name: String) -> some View {
        VStack(spacing: 4) {
            AsyncImage(url: URL(string: "https://images.evetech.net/corporations/\(corporationId)/logo?size=64")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .frame(width: 36, height: 36)
                default:
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white.opacity(0.1))
                        .frame(width: 36, height: 36)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.3), radius: 4)

            Text(name)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
