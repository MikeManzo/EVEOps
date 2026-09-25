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

// MARK:  Advanced Tab

struct AdvancedTab: View {
    @AppStorage("esiServer") private var esiServer: String = "tranquility"
    @AppStorage("debugMode") private var debugMode = false
    @AppStorage("sidebar.showUtility") private var showUtilitySection = true
    @AppStorage("diagMaxEntries") private var diagMaxEntries: Int = 1000
    @AppStorage("diagMaxDays") private var diagMaxDays: Int = 7

    private var logStore: DiagnosticLogStore { DiagnosticLogStore.shared }
    @State private var logFileSize: String = ""

    private func refreshFileSize() {
        let path = DiagnosticLogStore.storageURL.path
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let bytes = attrs[.size] as? Int64, bytes > 0 {
            logFileSize = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        } else if !logStore.entries.isEmpty,
                  let data = try? JSONEncoder().encode(logStore.entries) {
            logFileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
        } else {
            logFileSize = "0 KB"
        }
    }

    var body: some View {
        Form {
            Section("ESI Server") {
                Picker("Server", selection: $esiServer) {
                    Text("Tranquility (Live)").tag("tranquility")
                    Text("Singularity (Test)").tag("singularity")
                }
                .pickerStyle(.radioGroup)
                Text("Changing the server requires a restart to take effect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Debug") {
//                Toggle("Debug mode", isOn: $debugMode)
//                Text("Logs additional diagnostic information to the console.")
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
                VStack (alignment: .leading, spacing: 10) {
                    Toggle("Show Utility section in sidebar", isOn: $showUtilitySection)
                    Text("Displays the Utility section containing the Diagnostic Logs viewer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Max log entries") {
                    EVEMenuPicker("Max log entries", selection: $diagMaxEntries,
                                  options: [250, 500, 1000, 2500, 5000].map { EVEMenuOption($0, verbatim: $0.formatted()) })
                }
                LabeledContent("Keep logs for") {
                    EVEMenuPicker("Keep logs for", selection: $diagMaxDays, options: [
                        EVEMenuOption(1, "1 day"),
                        EVEMenuOption(3, "3 days"),
                        EVEMenuOption(7, "7 days"),
                        EVEMenuOption(14, "14 days"),
                        EVEMenuOption(30, "30 days"),
                    ])
                }
                HStack {
                    Button("Clear Log Now") {
                        logStore.clear()
                        refreshFileSize()
                    }
                    .foregroundStyle(.red)
                    if !logFileSize.isEmpty {
                        Text(logFileSize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear { refreshFileSize() }
                .onChange(of: logStore.entries.count) { refreshFileSize() }
            }
        }
        .formStyle(.grouped)
    }
}
