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
import AppKit

/// The app's main-menu commands and keyboard shortcuts.
///
/// EVEOps ships only a `MenuBarExtra` scene and drives its windows from
/// `WindowService`, so before this there was no File/View/Window menu and not a
/// single keyboard shortcut. When the Dock icon is hidden (the default) the menu
/// bar itself isn't drawn, but the key equivalents below still fire whenever an
/// EVEOps window is focused.
///
/// Commands can't touch `MainContentView`'s local state directly, so section /
/// palette / refresh intents are posted through `AppRouter` (the same channel
/// `AppDelegate` already uses for opened files).
struct AppCommands: Commands {
    var updater: AppUpdater

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About EVEOps") { WindowService.shared.showAbout() }
            Button("Check for Updates…") { updater.checkForUpdates() }
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Find…") { AppRouter.shared.requestFind() }
                .keyboardShortcut("f", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { WindowService.shared.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }

        // File → replace the inert "New" entry with something useful.
        CommandGroup(replacing: .newItem) {
            Button("Add Character…") { AppRouter.shared.requestAddCharacter() }
                .keyboardShortcut("n", modifiers: .command)
        }

        CommandMenu("Go") {
            Button("Quick Switcher…") { AppRouter.shared.openCommandPalette() }
                .keyboardShortcut("k", modifiers: .command)
            Button("Refresh") { AppRouter.shared.requestRefresh() }
                .keyboardShortcut("r", modifiers: .command)

            Divider()

            Button("Dashboard") { AppRouter.shared.pendingSection = .dashboard }
                .keyboardShortcut("0", modifiers: .command)
            Button("Previous Section") { AppRouter.shared.stepSection(-1) }
                .keyboardShortcut("[", modifiers: .command)
            Button("Next Section") { AppRouter.shared.stepSection(1) }
                .keyboardShortcut("]", modifiers: .command)

            Divider()

            ForEach(Array(NavigationSection.quickJumpSlots.enumerated()), id: \.offset) { index, section in
                Button(section.rawValue) { AppRouter.shared.pendingSection = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }

        CommandGroup(after: .windowArrangement) {
            Button("Galaxy Market Search") { WindowService.shared.showGalaxySearch() }
            Button("Trade Hub Comparison") { WindowService.shared.showTradeHubComparison() }
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") {
                WindowService.shared.showMain()
                AppRouter.shared.showKeyboardShortcuts()
            }
            .keyboardShortcut("/", modifiers: .command)
            Button("What’s New in EVEOps") {
                WindowService.shared.showMain()
                AppRouter.shared.showWhatsNew()
            }
            Divider()
            Button("EVEOps on GitHub") {
                if let url = URL(string: "https://github.com/MikeManzo/EVEOps") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}
