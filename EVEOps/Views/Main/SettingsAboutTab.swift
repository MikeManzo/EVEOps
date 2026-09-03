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

// MARK:  About Tab

struct AboutTab: View {
    @State var glowPulse = false
    @State var ringRotation: Double = 0
    @State var legalExpanded = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            // Background
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.03, green: 0.05, blue: 0.14),
                        Color(red: 0.07, green: 0.04, blue: 0.11)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Deterministic starfield
                Canvas { context, size in
                    let w = max(Int(size.width), 1)
                    let h = max(Int(size.height), 1)
                    for i in 0..<60 {
                        let x = CGFloat((i * 137 + 73) % w)
                        let y = CGFloat((i * 239 + 41) % h)
                        let r: CGFloat = (i % 4 == 0) ? 1.1 : 0.55
                        let opacity = Double(i % 8) / 22.0 + 0.1
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                            with: .color(Color.white.opacity(opacity))
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.93, green: 0.95, blue: 1.0),
                        Color(red: 0.87, green: 0.90, blue: 0.97)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Content
            ScrollView {
                VStack(spacing: 0) {
                    // Hero: icon + title + version
                    VStack(spacing: 10) {
                        iconHero
                        Text("EVEOps")
                            .font(.system(size: 26, weight: .bold))
                            .tracking(0.5)
                        versionPill
                    }
                    .padding(.top, 28)

                    // Gradient rule
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .primary.opacity(0.12), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 0.5)
                        .padding(.horizontal, 44)
                        .padding(.top, 18)

                    // Feature chips
                    HStack(spacing: 8) {
                        chip("antenna.radiowaves.left.and.right", "ESI API")
                        chip("lock.shield", "PKCE Auth")
                        chip("internaldrive", "Smart Cache")
                        chip("bell", "Notifications")
                        chip("apple.intelligence", "Intelligence")
                    }
                    .padding(.top, 16)

                    // Developer links
                    HStack(spacing: 10) {
                        linkButton("doc.text.magnifyingglass", "ESI Reference") {
                            if let url = URL(string: "https://esi.evetech.net/ui/") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        linkButton("globe", "EVE Developers") {
                            if let url = URL(string: "https://developers.eveonline.com") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        linkButton("qrcode", "Github") {
                            if let url = URL(string: "https://github.com/MikeManzo/EVEOps") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        linkButton("server.rack", "KEC Discord") {
                            if let url = URL(string: "https://discord.gg/HjRK7yAH8") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .padding(.top, 12)

                    // EVE Buddy standing card
                    eveBuddyCard
                        .padding(.top, 14)

                    // zKillboard attribution card
                    zkillboardCard
                        .padding(.top, 8)

                    // Fuzzwork attribution card
                    fuzzworkCard
                        .padding(.top, 8)
                    
                    // EVEShipFit dogmaEngine card
                    dogmaEngineCard
                        .padding(.top, 8)

                    // Janice attribution card
                    janiceCard
                        .padding(.top, 8)
                    
                    // Claude Code attribution card
                    claudeCodeCard
                        .padding(.top, 8)
                    
                    // EVE Scout
                    scoutCard
                        .padding(.top, 8)

                    // EVERef attribution card
                    eveRefCard
                        .padding(.top, 8)

                    // GetEveModels attribution card
                    getEveModelsCard
                        .padding(.top, 8)

                    // Sparkle attribution card
                    sparkleCard
                        .padding(.top, 8)

                    // Anoik.is attribution card
                    anoikCard
                        .padding(.top, 8)

                    // Special Thanks section
                    Label("Special Thanks", systemImage: "heart.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 44)
                        .padding(.top, 14)

                    // Kerreah character card
                    kerreahCard
                        .padding(.top, 8)

                    // Idle Boy character card
                    idleBoyCard
                        .padding(.top, 8)

                    // Collapsible legal
                    DisclosureGroup(isExpanded: $legalExpanded) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("EVE Online and the EVE logo are registered trademarks of Fenris Creations. All rights reserved worldwide.")
                            Text("EVEOps is an independent third-party application not affiliated with, endorsed by, or sponsored by Fenris Creations.")
                            Text("All EVE Online related materials are used in accordance with the EVE Online Third-Party Developer License Agreement.")
                            Text("\"EVE\", \"EVE Online\", \"Fenris\", and all related logos are trademarks of Fenris Creations.")

                            Divider()
                                .padding(.vertical, 2)

                            Text("Sparkle is copyright © Andy Matuschak and contributors. Used under the MIT License. \"Sparkle\" is a trademark of its respective authors.")
                            Text("zKillboard is a service provided by zKillboard.com. Killmail data is consumed via the public zKillboard API.")
                            Text("Fuzzwork Enterprises market data is provided courtesy of Steve Ronuken (fuzzwork.co.uk). Used with permission under the public API terms.")
                            Text("Janice appraisal data is provided by e-351.com. Used in accordance with the Janice public API terms of service.")
                            Text("EVERef reference data is provided by Autonomous Logic. Used under the EVERef public API terms. Not affiliated with or endorsed by CCP.")
                            Text("EVEScout and the EVEScout logo/name are trademarks and/or service marks of EVEScout.")
                            Text("EVEShip.fit and its Dogma Engine are copyright EVEShipFit contributors. Used under open-source license terms.")
                            Text("Claude and Claude Code are trademarks of Anthropic, PBC. Used for AI-assisted development. No user data is transmitted to Anthropic by EVEOps.")
                            Text("GetEveModels provides 3D ship model data for EVE Online. Used in accordance with the GetEveModels public API terms of service.")
                            Text("Anoik.is is a third-party wormhole system database for EVE Online. Used in accordance with the Anoik.is public API terms of service.")
                            Text("EVE Buddy is acknowledged as an inspiration for EVEOps and is not affiliated with or endorsed by this application.")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                    } label: {
                        Label("Legal Notices", systemImage: "doc.text")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 44)
                    .padding(.top, 14)

                    Text("\u{00A9} \(currentYear) CitizenCoder  ·  Not affiliated with Fenris Creations.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                ringRotation = 360
            }
        }
    }

    // Mark:  Icon hero

}
