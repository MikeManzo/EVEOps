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

// MARK: Watched contacts strip

/// The contacts you've marked "watched" in EVE, as one compact row of portraits and
/// logos. The Dashboard used to show every contact — players, NPC agents and
/// organizations — as full cards, which repeated the Contacts screen and buried
/// everything below it.
struct DashboardWatchedContactsStrip: View {
    let contacts: [ContactSummary]

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        HStack(spacing: EVESpacing.md) {
            Image(systemName: "eye.fill")
                .foregroundStyle(themeManager.palette.accent)
                .font(.callout)
            Text("Watched")
                .font(.title3.bold())

            ScrollView(.horizontal) {
                HStack(spacing: EVESpacing.sm) {
                    ForEach(contacts) { contact in
                        avatar(contact)
                    }
                }
                .padding(.vertical, EVESpacing.xxs)
            }
            .scrollIndicators(.never)

            Button {
                AppRouter.shared.pendingSection = .contacts
            } label: {
                Label("All Contacts", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            }
            .buttonStyle(.link)
            .help("Open Contacts")
        }
        .padding(.horizontal, EVESpacing.lg)
        .padding(.vertical, EVESpacing.md)
        .background(themeManager.palette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: EVERadius.lg))
        .overlay(RoundedRectangle(cornerRadius: EVERadius.lg).strokeBorder(themeManager.palette.accent.opacity(0.15), lineWidth: 1))
    }

    private func avatar(_ contact: ContactSummary) -> some View {
        let isCharacter = contact.contactType == "character"
        let shape = RoundedRectangle(cornerRadius: isCharacter ? 16 : EVERadius.sm)
        return CachedAsyncImage(url: contact.imageURL) { image in
            image.resizable()
        } placeholder: {
            shape.fill(.quaternary)
        }
        .frame(width: 32, height: 32)
        .clipShape(shape)
        .overlay(shape.strokeBorder(eveStandingColor(contact.standing).opacity(0.8), lineWidth: 1.5))
        .help(helpText(contact))
        .eveContextMenu(contact.entity)
        .accessibilityLabel(Text(contact.name.isEmpty ? String(localized: "Contact") : contact.name))
    }

    private func helpText(_ contact: ContactSummary) -> String {
        let standing = contact.standing.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
        let org = contact.corporationName.isEmpty ? "" : " · \(contact.corporationName)"
        return "\(contact.name)\(org) · standing \(standing)"
    }
}

extension ContactSummary {
    /// The contact as a right-clickable entity.
    var entity: EVEEntity? {
        guard !name.isEmpty else { return nil }
        switch contactType {
        case "character":   return .character(id: contactID, name: name)
        case "corporation": return .corporation(id: contactID, name: name)
        case "alliance":    return .alliance(id: contactID, name: name)
        default:            return nil
        }
    }
}
