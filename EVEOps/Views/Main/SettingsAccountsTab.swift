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

// MARK:  Accounts Tab

struct AccountsTab: View {
    @Environment(AccountManager.self) private var accountManager
    @Environment(DashboardPrefetcher.self) private var prefetcher

    var body: some View {
        VStack(spacing: 0) {
            if accountManager.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No Characters Added")
                        .font(.headline)
                    Text("Add your EVE Online characters to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add Character") {
                        Task { await accountManager.addAccount() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(accountManager.isLoading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                if let selected = accountManager.selectedAccount {
                    CharacterDossierCard(
                        account: selected,
                        summary: prefetcher.menuBarSummaries[selected.characterID],
                        onDelete: { accountManager.removeAccount(selected) }
                    )
                }
                let others = accountManager.accounts.filter {
                    $0.characterID != accountManager.selectedCharacterID
                }
                if !others.isEmpty {
                    List(others, id: \.characterID) { account in
                        AccountRowView(account: account)
                    }
                    .listStyle(.inset)
                } else {
                    Spacer()
                }
            }

            Divider()

            HStack {
                Button {
                    Task { await accountManager.addAccount() }
                } label: {
                    Label("Add Character", systemImage: "plus")
                }
                .disabled(accountManager.isLoading)

                if accountManager.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 4)
                }

                Spacer()

                if let error = accountManager.error {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(8)
        }
    }
}

struct AccountRowView: View {
    @Environment(AccountManager.self) private var accountManager
    let account: StoredAccount
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                image.resizable()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(account.characterName)
                    .fontWeight(.medium)
                Text(account.corporationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if account.needsReauth {
                Button {
                    Task { await accountManager.reauthorize(account) }
                } label: {
                    Label("Re-authenticate", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.orange)
                .disabled(accountManager.isLoading)
            } else {
                Label("Active", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                "Remove \(account.characterName)?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    accountManager.removeAccount(account)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Character Dossier Card

struct CharacterDossierCard: View {
    @Environment(AccountManager.self) private var accountManager
    let account: StoredAccount
    let summary: CharacterSummary?
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(spacing: 10) {
            // Header: portrait + identity + online badge only
            HStack(spacing: 12) {
                CachedAsyncImage(url: EVEImageURL.characterPortrait(account.characterID, size: 128)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(.quaternary)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.characterName)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(summary?.corporationName.isEmpty == false ? summary!.corporationName : account.corporationName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let alliance = summary?.allianceName ?? account.allianceName {
                        Text(alliance)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    if let online = summary?.online {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(online ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 6, height: 6)
                            Text(online ? "Online" : "Offline")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(online ? .green : .secondary)
                        }
                    }
                    if account.needsReauth {
                        Button {
                            Task { await accountManager.reauthorize(account) }
                        } label: {
                            Label("Re-authenticate", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                        .disabled(accountManager.isLoading)
                    } else {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    }
                }
            }

            // Stats strip — includes token status and remove action
            HStack(spacing: 0) {
                statCell(
                    icon: "banknote",
                    color: .green,
                    label: "WALLET",
                    value: summary.map { EVEFormatters.formatISKShort($0.wallet) } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "chart.bar.fill",
                    color: .blue,
                    label: "SKILL PTS",
                    value: summary.map { formatSP($0.totalSP) } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "graduationcap.fill",
                    color: .purple,
                    label: "IN QUEUE",
                    value: summary.map { "\($0.skillQueueCount)" } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "location.fill",
                    color: securityColor(summary?.securityStatus),
                    label: "SYSTEM",
                    value: summary.map { $0.systemName.isEmpty ? "--" : $0.systemName } ?? "--"
                )
                stripDivider
                statCell(
                    icon: "diamond.fill",
                    color: .cyan,
                    label: "SHIP",
                    value: summary.map { $0.shipTypeName.isEmpty ? "--" : $0.shipTypeName } ?? "--"
                )
                stripDivider
                // Remove action cell
                Button {
                    showDeleteConfirm = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("Remove")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.red)
                        Text("CHARACTER")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .confirmationDialog(
                    "Remove \(account.characterName)?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive, action: onDelete)
                }
            }
            .padding(.vertical, 8)
            .background(.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.06)))
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.primary.opacity(0.07)))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private func statCell(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(.primary.opacity(0.08))
            .frame(width: 0.5)
            .padding(.vertical, 6)
    }

    private func formatSP(_ sp: Int) -> String {
        if sp >= 1_000_000 { return String(format: "%.1fM", Double(sp) / 1_000_000) }
        if sp >= 1_000 { return String(format: "%.0fK", Double(sp) / 1_000) }
        return "\(sp)"
    }

    private func securityColor(_ sec: Double?) -> Color {
        guard let sec else { return .orange }
        if sec >= 0.5 { return .green }
        if sec > 0.0 { return .yellow }
        return .red
    }
}
