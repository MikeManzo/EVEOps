//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// MARK: Backup menu

/// Settings > Accounts: export/import an encrypted pilot backup, and re-run the restore
/// that normally happens automatically at launch.
struct PilotBackupMenu: View {
    @Environment(AccountManager.self) private var accountManager

    private enum Sheet: Identifiable {
        case export
        case importing(Data)

        var id: String {
            switch self {
            case .export: "export"
            case .importing: "import"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var resultMessage: String?

    private var backupType: UTType {
        UTType(filenameExtension: PilotBackupFile.fileExtension) ?? .data
    }

    var body: some View {
        Menu {
            Button("Export Backup…") { sheet = .export }
                .disabled(accountManager.accounts.isEmpty)
            Button("Import Backup…", action: chooseBackupToImport)
            Divider()
            Button("Restore Missing Pilots", action: restoreMissing)
        } label: {
            Label("Backup", systemImage: "externaldrive.badge.timemachine")
        }
        .menuStyle(.button)
        .fixedSize()
        .disabled(accountManager.isLoading)
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .export:
                PilotBackupPassphraseSheet(mode: .export) { passphrase in
                    self.sheet = nil
                    Task { await export(passphrase: passphrase) }
                } onCancel: {
                    self.sheet = nil
                }
            case .importing(let file):
                PilotBackupPassphraseSheet(mode: .importing) { passphrase in
                    self.sheet = nil
                    Task { await importBackup(file, passphrase: passphrase) }
                } onCancel: {
                    self.sheet = nil
                }
            }
        }
        .alert("Pilot Backup", isPresented: Binding(
            get: { resultMessage != nil },
            set: { if !$0 { resultMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(resultMessage ?? "")
        }
    }

    // MARK: Actions

    private func export(passphrase: String) async {
        do {
            let data = try await accountManager.makeBackup(passphrase: passphrase)

            let panel = NSSavePanel()
            panel.allowedContentTypes = [backupType]
            panel.nameFieldStringValue = "EVEOps Pilots \(Self.dateStamp).\(PilotBackupFile.fileExtension)"
            panel.message = "Choose where to save the encrypted pilot backup."
            guard panel.runModal() == .OK, let url = panel.url else { return }

            try data.write(to: url, options: .atomic)
            // The file is encrypted, but there's still no reason for it to be world-readable.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            Logger.auth.info("Backup: saved encrypted backup of \(accountManager.accounts.count) pilot(s) to \(url.lastPathComponent)")
            resultMessage = "Saved an encrypted backup of \(accountManager.accounts.count) pilot(s) to \(url.lastPathComponent). Keep the passphrase safe — it can't be recovered."
        } catch {
            Logger.auth.error("Backup: export failed — \(error.localizedDescription)")
            resultMessage = "Couldn't create the backup: \(error.localizedDescription)"
        }
    }

    private func chooseBackupToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [backupType]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an EVEOps pilot backup file."
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            sheet = .importing(try Data(contentsOf: url))
        } catch {
            resultMessage = "Couldn't read that file: \(error.localizedDescription)"
        }
    }

    private func importBackup(_ file: Data, passphrase: String) async {
        do {
            let result = try await accountManager.importBackup(file, passphrase: passphrase)
            var parts: [String] = []
            if !result.added.isEmpty { parts.append("Added \(result.added.joined(separator: ", "))") }
            if !result.updated.isEmpty { parts.append("Updated login for \(result.updated.joined(separator: ", "))") }
            resultMessage = parts.isEmpty
                ? "Everything in that backup is already up to date."
                : parts.joined(separator: ". ") + "."
        } catch {
            Logger.auth.error("Backup: import failed — \(error.localizedDescription)")
            resultMessage = error.localizedDescription
        }
    }

    private func restoreMissing() {
        let restored = accountManager.restoreMissingPilots()
        resultMessage = restored.isEmpty
            ? "No missing pilots were found in the backup."
            : "Restored \(restored.joined(separator: ", "))."
    }

    private static var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: Passphrase sheet

struct PilotBackupPassphraseSheet: View {
    enum Mode { case export, importing }

    let mode: Mode
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var passphrase = ""
    @State private var confirmation = ""

    private var isValid: Bool {
        switch mode {
        case .export:
            passphrase.count >= PilotBackupFile.minimumPassphraseLength && passphrase == confirmation
        case .importing:
            !passphrase.isEmpty
        }
    }

    private var hint: String? {
        guard mode == .export, !passphrase.isEmpty else { return nil }
        if passphrase.count < PilotBackupFile.minimumPassphraseLength {
            return "Use at least \(PilotBackupFile.minimumPassphraseLength) characters."
        }
        if !confirmation.isEmpty, passphrase != confirmation { return "Passphrases don't match." }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(mode == .export ? "Encrypt Pilot Backup" : "Unlock Pilot Backup")
                .font(.headline)
            Text(mode == .export
                 ? "The backup contains login tokens for your characters. This passphrase encrypts them — there's no way to recover it if you forget it."
                 : "Enter the passphrase this backup was encrypted with.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("Passphrase", text: $passphrase)
            if mode == .export {
                SecureField("Confirm passphrase", text: $confirmation)
            }
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(mode == .export ? "Export…" : "Import") { onSubmit(passphrase) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 380)
    }
}
