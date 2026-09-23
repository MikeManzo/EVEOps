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

extension AboutTab {
    var iconHero: some View {
        ZStack {
            // Pulsing ambient glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hue: 0.62, saturation: 0.8, brightness: 1.0)
                                .opacity(glowPulse ? 0.28 : 0.08),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 68
                    )
                )
                .frame(width: 136, height: 136)

            // Rotating comet-sweep ring
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .blue.opacity(0), location: 0.0),
                            .init(color: .blue, location: 0.3),
                            .init(color: .cyan, location: 0.55),
                            .init(color: .purple, location: 0.75),
                            .init(color: .blue.opacity(0), location: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: 2.5
                )
                .frame(width: 104, height: 104)
                .rotationEffect(.degrees(ringRotation))

            // App icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        }
    }

    // Mark:  Version pill

    @ViewBuilder
    var versionPill: some View {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 5, height: 5)
                Text("v\(version)  ·  Build \(build)")
                    .font(.eveCaptionMedium)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.primary.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.1)))
        }
    }

    // Mark:  EVE Buddy acknowledgement

    var eveBuddyCard: some View {
        HStack(spacing: 14) {
            // Max-standing gold star badge
            ZStack {
                Circle()
                    .fill(Color(hue: 0.12, saturation: 0.85, brightness: 1.0).opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "star.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(Color(hue: 0.12, saturation: 0.9, brightness: 1.0))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVE Buddy")
                    .font(.eveRowTitle)
                Text("ACKNOWLEDGED INSPIRATION")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("+10.0")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hue: 0.33, saturation: 0.65, brightness: 0.80))
                Text("STANDING")
                    .font(.eveBadge)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color(hue: 0.12, saturation: 0.85, brightness: 1.0).opacity(0.35),
                            Color(hue: 0.12, saturation: 0.85, brightness: 1.0).opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  zKillboard attribution card

    var zkillboardCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "heart.badge.bolt.slash")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("zKillboard")
                    .font(.eveRowTitle)
                Text("COMMUNITY FIT DATA SOURCE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("zkillboard.com") {
                if let url = URL(string: "https://zkillboard.com") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.red.opacity(0.30),
                            Color.red.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  dogmaEngine attribution card

    var janiceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "cart.circle")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Live EVE item Apprasial")
                    .font(.eveRowTitle)
                Text("LIVE APPRAISAL DATA SOURCE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Janice Pricing") {
                if let url = URL(string: "https://janice.e-351.com/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.30),
                            Color.green.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  sparkle attribution card

    var sparkleCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "arrowshape.up")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sparkle")
                    .font(.eveRowTitle)
                Text("SOFTWARE UPDATE FRAMEWORK")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Sparkle") {
                if let url = URL(string: "https://github.com/sparkle-project/Sparkle") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Anoik.is attribution card

    var anoikCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "globe.americas.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Anoik.is")
                    .font(.eveRowTitle)
                Text("WORMHOLE SYSTEM DATABASE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("anoik.is") {
                if let url = URL(string: "https://anoik.is") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.30),
                            Color.cyan.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  sparkle attribution card

    var scoutCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "service.dog.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Scout")
                    .font(.eveRowTitle)
                Text("WORMHOLE CONNECTIONS")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("EVE Scout") {
                if let url = URL(string: "https://www.eve-scout.com/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.30),
                            Color.blue.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    
    
    // Mark:  dogmaEngine attribution card

    var dogmaEngineCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "esim")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVEShip.fit's Dogma Engine")
                    .font(.eveRowTitle)
                Text("SHIP FIT SIM ENGINE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("EVEShip.fit") {
                if let url = URL(string: "https://eveship.fit") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.30),
                            Color.orange.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }
    
    // Mark:  Fuzzwork attribution card

    var fuzzworkCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "chart.bar.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Fuzzwork Enterprises")
                    .font(.eveRowTitle)
                Text("MARKET PRICE DATA SOURCE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("market.fuzzwork.co.uk") {
                if let url = URL(string: "https://market.fuzzwork.co.uk") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.30),
                            Color.green.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Claude Code attribution card

    var claudeCodeCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "wand.and.stars")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code")
                    .font(.eveRowTitle)
                Text("AI DEVELOPMENT ASSISTANT")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("claude.ai/code") {
                if let url = URL(string: "https://claude.ai/code") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.purple.opacity(0.30),
                            Color.purple.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  EVERef attribution card

    var eveRefCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.teal.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "books.vertical.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVERef")
                    .font(.eveRowTitle)
                Text("ITEM & BLUEPRINT REFERENCE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("everef.net") {
                if let url = URL(string: "https://everef.net") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.teal.opacity(0.30),
                            Color.teal.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  GetEveModels attribution card

    var getEveModelsCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.indigo.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "cube.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("GetEveModels")
                    .font(.eveRowTitle)
                Text("3D SHIP MODEL DATA SOURCE")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("getevemodels") {
                if let url = URL(string: "https://github.com/puffingprie/GetEveModels") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(0.30),
                            Color.indigo.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Kerreah character card

    var kerreahCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "person.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Kerreah")
                    .font(.eveRowTitle)
                Text("EVE CAPSULEER")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("zkillboard.com") {
                if let url = URL(string: "https://zkillboard.com/search/Kerreah/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.cyan.opacity(0.30),
                            Color.cyan.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Idle Boy character card

    var idleBoyCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: "person.fill")
                    .font(.eveSectionTitle)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Idle Boy")
                    .font(.eveRowTitle)
                Text("EVE CAPSULEER")
                    .font(.eveMicroBold)
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("zkillboard.com") {
                if let url = URL(string: "https://zkillboard.com/search/Idle%20Boy/") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.eveCaptionMedium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: EVERadius.lg, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.orange.opacity(0.30),
                            Color.orange.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .padding(.horizontal, 44)
    }

    // Mark:  Helpers

    func chip(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.eveLabelSemibold)
                .foregroundStyle(.blue)
            Text(label)
                .font(.eveCaptionMedium)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: EVERadius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: EVERadius.md, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    func linkButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.eveCaption)
                Text(label)
                    .font(.eveCalloutMedium)
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: EVERadius.md, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: EVERadius.md, style: .continuous).strokeBorder(.blue.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    var currentYear: String {
        Calendar.current.component(.year, from: Date()).description
    }
}
