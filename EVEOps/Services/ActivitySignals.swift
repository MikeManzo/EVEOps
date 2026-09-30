//
// This file is part of EVEOps.
//
// EVEOps is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 or later.
//
// Copyright (c) 2026 CitizenCoder
//

import Foundation
import Observation

/// Unread mail and notification counts per character, published by the background
/// poller (`NotificationService`) for the sidebar's badges. Each count also has an
/// arrival counter that only goes up when the unread count rises, so the sidebar can
/// wiggle an icon for "something new" without reacting to things being read.
@MainActor
@Observable
final class ActivitySignals {
    static let shared = ActivitySignals()

    private(set) var unreadMail: [Int: Int] = [:]
    private(set) var unreadNotifications: [Int: Int] = [:]
    private(set) var mailArrivals: [Int: Int] = [:]
    private(set) var notificationArrivals: [Int: Int] = [:]

    private init() {}

    func setUnreadMail(_ count: Int, for characterID: Int) {
        if let previous = unreadMail[characterID], count > previous {
            mailArrivals[characterID, default: 0] += 1
        }
        unreadMail[characterID] = count
    }

    func setUnreadNotifications(_ count: Int, for characterID: Int) {
        if let previous = unreadNotifications[characterID], count > previous {
            notificationArrivals[characterID, default: 0] += 1
        }
        unreadNotifications[characterID] = count
    }
}
