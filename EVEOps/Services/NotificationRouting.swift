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
import UserNotifications

/// Where an EVEOps alert leads: its notification category (and the action button that
/// category shows), and the sidebar section clicking the alert opens. Clicking also
/// switches to the pilot the alert is about, via `userInfo`.
nonisolated enum NotificationRoute {
    static let sectionKey = "eveops.section"
    static let characterKey = "eveops.characterID"
    static let openActionID = "eveops.open"

    /// Section an alert of this kind opens, if any.
    static func section(for category: DiscordAlertCategory) -> NavigationSection? {
        switch category {
        case .skillQueue:     return .training
        case .industry:       return .industry
        case .contracts:      return .contracts
        case .structureAlert,
             .structureFuel:  return .corpStructures
        case .war:            return .corpWars
        case .standings:      return .standings
        case .presence:       return .contacts
        case .serverStatus, .test, .general: return nil
        }
    }

    /// Notification category ID for a section; one category per destination so each can
    /// carry its own "Open …" button.
    static func categoryID(for section: NavigationSection) -> String {
        "eveops.open.\(section.rawValue)"
    }

    /// Every "Open …" category, for registration alongside the updater's.
    static var categories: Set<UNNotificationCategory> {
        let sections: [(NavigationSection, String)] = [
            (.training,       String(localized: "Open Training")),
            (.industry,       String(localized: "Open Industry")),
            (.contracts,      String(localized: "Open Contracts")),
            (.corpStructures, String(localized: "Open Structures")),
            (.corpWars,       String(localized: "Open Wars")),
            (.standings,      String(localized: "Open Standings")),
            (.contacts,       String(localized: "Open Contacts")),
        ]
        return Set(sections.map { section, title in
            UNNotificationCategory(
                identifier: categoryID(for: section),
                actions: [UNNotificationAction(identifier: openActionID, title: title, options: [.foreground])],
                intentIdentifiers: [],
                options: []
            )
        })
    }

    /// Handles a click on (or the "Open …" button of) an EVEOps alert. Returns false for
    /// notifications that aren't routable, so the caller can handle them itself.
    @MainActor
    static func handle(_ response: UNNotificationResponse) -> Bool {
        let info = response.notification.request.content.userInfo
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier
                || response.actionIdentifier == openActionID,
              let raw = info[sectionKey] as? String,
              let section = NavigationSection(rawValue: raw) else { return false }
        if let characterID = info[characterKey] as? Int {
            AppRouter.shared.pendingCharacterID = characterID
        }
        AppRouter.shared.pendingSection = section
        WindowService.shared.showMain()
        return true
    }

    /// Copies an image into a temporary file for use as a notification attachment — the
    /// notification center requires a file URL and takes ownership of (moves) the file.
    static func attachment(for image: NSImage, identifier: String) -> UNNotificationAttachment? {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("eveops-notification-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: identifier, url: url, options: nil)
        } catch {
            return nil
        }
    }
}
