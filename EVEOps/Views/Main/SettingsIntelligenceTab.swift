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
import FoundationModels

// Mark:  Intelligence Tab

struct IntelligenceTab: View {
    @AppStorage("aiInsightsEnabled") private var aiInsightsEnabled = false

    var body: some View {
        if #available(macOS 26.0, *) {
            IntelligenceTabContent(aiInsightsEnabled: $aiInsightsEnabled)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "brain")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("Apple Intelligence requires macOS 26 or later.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

@available(macOS 26.0, *)
struct IntelligenceTabContent: View {
    @Binding var aiInsightsEnabled: Bool
    private var model: SystemLanguageModel { .default }

    @AppStorage("aiInsightFinances")          private var aiInsightFinances          = true
    @AppStorage("aiInsightSkills")            private var aiInsightSkills            = true
    @AppStorage("aiInsightKillmails")         private var aiInsightKillmails         = true
    @AppStorage("aiInsightIndustry")          private var aiInsightIndustry          = true
    @AppStorage("aiInsightAssets")            private var aiInsightAssets            = true
    @AppStorage("aiInsightFittings")          private var aiInsightFittings          = true
    @AppStorage("aiInsightCommunityFittings") private var aiInsightCommunityFittings = true
    @AppStorage("aiInsightMarket")            private var aiInsightMarket            = true
    @AppStorage("aiInsightClones")            private var aiInsightClones            = true

    var body: some View {
        Form {
            Section("Apple Intelligence") {
                switch model.availability {
                case .available:
                    Toggle("Enable AI Insights", isOn: $aiInsightsEnabled)
                    Text("Uses the on-device Apple Intelligence to analyze your financial and skill training data. All processing is local — no data leaves your Mac.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .unavailable(.appleIntelligenceNotEnabled):
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apple Intelligence Not Enabled")
                                .fontWeight(.medium)
                            Text("Turn on Apple Intelligence in System Settings to use AI Insights.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    Button("Open System Settings\u{2026}") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.siri") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)

                case .unavailable(.deviceNotEligible):
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Device Not Eligible")
                                .fontWeight(.medium)
                            Text("Apple Intelligence requires Apple Silicon. This Mac is not supported.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }

                case .unavailable(.modelNotReady):
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Model Downloading")
                                .fontWeight(.medium)
                            Text("The on-device model is still initializing. Check back shortly.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(.blue)
                    }

                default:
                    Text("Apple Intelligence is not available on this device.")
                        .foregroundStyle(.secondary)
                }
            }

            if aiInsightsEnabled, case .available = model.availability {
                Section("Individual Insights") {
                    Toggle(isOn: $aiInsightFinances) {
                        Label("Finances", systemImage: "banknote")
                    }
                    Toggle(isOn: $aiInsightSkills) {
                        Label("Skill Planner", systemImage: "graduationcap")
                    }
                    Toggle(isOn: $aiInsightKillmails) {
                        Label("Kill/Loss Mails", systemImage: "flame")
                    }
                    Toggle(isOn: $aiInsightIndustry) {
                        Label("Industry", systemImage: "hammer")
                    }
                    Toggle(isOn: $aiInsightAssets) {
                        Label("Assets", systemImage: "cube.box")
                    }
                    Toggle(isOn: $aiInsightFittings) {
                        Label("Fittings", systemImage: "cpu")
                    }
                    Toggle(isOn: $aiInsightCommunityFittings) {
                        Label("Community Fittings", systemImage: "person.2.wave.2")
                    }
                    Toggle(isOn: $aiInsightMarket) {
                        Label("Market Browser", systemImage: "chart.xyaxis.line")
                    }
                    Toggle(isOn: $aiInsightClones) {
                        Label("Clones & Implants", systemImage: "brain.head.profile")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
