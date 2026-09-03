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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hue: 0.12, saturation: 0.9, brightness: 1.0))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVE Buddy")
                    .font(.system(size: 13, weight: .semibold))
                Text("ACKNOWLEDGED INSPIRATION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text("+10.0")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hue: 0.33, saturation: 0.65, brightness: 0.80))
                Text("STANDING")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("zKillboard")
                    .font(.system(size: 13, weight: .semibold))
                Text("COMMUNITY FIT DATA SOURCE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Live EVE item Apprasial")
                    .font(.system(size: 13, weight: .semibold))
                Text("LIVE APPRAISAL DATA SOURCE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Sparkle")
                    .font(.system(size: 13, weight: .semibold))
                Text("SOFTWARE UPDATE FRAMEWORK")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Anoik.is")
                    .font(.system(size: 13, weight: .semibold))
                Text("WORMHOLE SYSTEM DATABASE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Scout")
                    .font(.system(size: 13, weight: .semibold))
                Text("WORMHOLE CONNECTIONS")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVEShip.fit's Dogma Engine")
                    .font(.system(size: 13, weight: .semibold))
                Text("SHIP FIT SIM ENGINE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Fuzzwork Enterprises")
                    .font(.system(size: 13, weight: .semibold))
                Text("MARKET PRICE DATA SOURCE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code")
                    .font(.system(size: 13, weight: .semibold))
                Text("AI DEVELOPMENT ASSISTANT")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.teal)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("EVERef")
                    .font(.system(size: 13, weight: .semibold))
                Text("ITEM & BLUEPRINT REFERENCE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.indigo)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("GetEveModels")
                    .font(.system(size: 13, weight: .semibold))
                Text("3D SHIP MODEL DATA SOURCE")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Kerreah")
                    .font(.system(size: 13, weight: .semibold))
                Text("EVE CAPSULEER")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Idle Boy")
                    .font(.system(size: 13, weight: .semibold))
                Text("EVE CAPSULEER")
                    .font(.system(size: 9, weight: .bold))
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
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.blue)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.08)))
    }

    func linkButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.blue)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.blue.opacity(0.18)))
        }
        .buttonStyle(.plain)
    }

    var currentYear: String {
        Calendar.current.component(.year, from: Date()).description
    }
}
