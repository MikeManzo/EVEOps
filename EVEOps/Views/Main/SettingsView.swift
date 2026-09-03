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
import ServiceManagement
import Sparkle
import FoundationModels

struct SettingsView: View {
    @State private var selection: SettingsSection?

    init(openToUpdate: Bool = false) {
        _selection = State(initialValue: openToUpdate ? .general : .accounts)
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, id: \.self, selection: $selection) { section in
                SettingsSidebarRow(section: section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 260)
        } detail: {
            let current = selection ?? .accounts
            Group {
                switch current {
                case .accounts:      AccountsTab()
                case .general:       GeneralTab()
                case .appearance:    AppearanceTab()
                case .notifications: NotificationsTab()
                case .cache:         CacheTab()
                case .advanced:      AdvancedTab()
                case .intelligence:  IntelligenceTab()
                case .about:         AboutTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(""/*current.title*/)
        }
        .frame(width: 780, height: 540)
    }
}

// MARK:  Sidebar Navigation Model

private enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case accounts, general, appearance, notifications, cache, advanced, intelligence, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accounts:      "Accounts"
        case .general:       "General"
        case .appearance:    "Appearance"
        case .notifications: "Notifications"
        case .cache:         "Cache & Data"
        case .advanced:      "Advanced"
        case .intelligence:  "Intelligence"
        case .about:         "About"
        }
    }

    var icon: String {
        switch self {
        case .accounts:      "person.2.fill"
        case .general:       "gearshape.fill"
        case .appearance:    "paintbrush.fill"
        case .notifications: "bell.fill"
        case .cache:         "internaldrive.fill"
        case .advanced:      "terminal.fill"
        case .intelligence:  "brain"
        case .about:         "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .accounts:      Color(red: 0.30, green: 0.52, blue: 0.80)
        case .general:       Color(white: 0.52)
        case .appearance:    Color(red: 0.57, green: 0.40, blue: 0.72)
        case .notifications: Color(red: 0.80, green: 0.32, blue: 0.32)
        case .cache:         Color(red: 0.28, green: 0.67, blue: 0.42)
        case .advanced:      Color(white: 0.40)
        case .intelligence:  Color(red: 0.40, green: 0.45, blue: 0.76)
        case .about:         Color(red: 0.24, green: 0.60, blue: 0.63)
        }
    }
}

private struct SettingsSidebarRow: View {
    let section: SettingsSection

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(section.iconColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}
