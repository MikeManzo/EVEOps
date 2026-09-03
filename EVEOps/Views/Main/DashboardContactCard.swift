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

// Mark:  Contact Card

struct ContactCardView: View {
    let contact: ContactSummary
    @Environment(PresenceTracker.self) private var presenceTracker

    var body: some View {
        VStack(spacing: 0) {
            // Banner: standing-tinted gradient + overlay logo
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(
                    colors: [standingColor.opacity(0.30), Color(white: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 80)

                if let bannerURL = contact.bannerLogoURL {
                    CachedAsyncImage(url: bannerURL) { phase in
                        if let image = phase.image {
                            image.resizable()
                                .frame(width: 32, height: 32)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .shadow(color: .black.opacity(0.5), radius: 3)
                        }
                    }
                    .padding(8)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                // Identity row
                HStack(spacing: 12) {
                    ZStack(alignment: .bottomTrailing) {
                        CachedAsyncImage(url: contact.imageURL) { image in
                            image.resizable()
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                        }
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.1), lineWidth: 1))

                        if contact.isPlayerCharacter {
                            PresenceBadge(score: presenceTracker.score(for: contact.contactID), size: 13)
                                .offset(x: 3, y: 3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(contact.name.isEmpty ? "Loading..." : contact.name)
                                .font(.headline)
                            Spacer()
                            if let sec = contact.securityStatus {
                                Text(String(format: "%.1f", sec))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(sec >= 0 ? .green : .red)
                            }
                        }
                        if let title = contact.title, !title.isEmpty {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !contact.corporationName.isEmpty {
                            Text(contact.corporationName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if let alliance = contact.allianceName {
                            Text(alliance)
                                .font(.caption)
                                .foregroundStyle(.secondary.opacity(0.6))
                        }
                    }
                }

                Divider()

                // Type badge + flags + standing
                HStack(spacing: 8) {
                    Image(systemName: contactTypeIcon)
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(contactTypeLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.blue)

                    if contact.isWatched {
                        Image(systemName: "eye.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("Watched")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if contact.isBlocked {
                        Image(systemName: "slash.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Text("Blocked")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: standingIcon)
                            .foregroundStyle(standingColor)
                            .font(.caption)
                        Text(String(format: "%.1f", contact.standing))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(standingColor)
                    }
                }

                // Label tags
                if !contact.labelNames.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(contact.labelNames, id: \.self) { label in
                                Text(label)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var contactTypeIcon: String {
        switch contact.contactType {
        case "corporation":                                return "building.2.fill"
        case "alliance":                                   return "shield.fill"
        case "faction":                                    return "globe"
        case "character" where contact.isPlayerCharacter:  return "person.fill"
        default:                                           return "cpu"
        }
    }

    private var contactTypeLabel: String {
        switch contact.contactType {
        case "corporation":                                return "Corp"
        case "alliance":                                   return "Alliance"
        case "faction":                                    return "Faction"
        case "character" where contact.isPlayerCharacter:  return "Player"
        default:                                           return "NPC"
        }
    }

    private var standingColor: Color {
        if contact.standing >= 5 { return .blue }
        if contact.standing > 0 { return .cyan }
        if contact.standing == 0 { return .gray }
        if contact.standing > -5 { return .orange }
        return .red
    }

    private var standingIcon: String {
        if contact.standing >= 5 { return "star.fill" }
        if contact.standing > 0 { return "hand.thumbsup.fill" }
        if contact.standing == 0 { return "minus" }
        if contact.standing > -5 { return "hand.thumbsdown.fill" }
        return "xmark.circle.fill"
    }
}
