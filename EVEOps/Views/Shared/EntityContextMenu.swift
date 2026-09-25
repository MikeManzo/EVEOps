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

/// Something in New Eden a user can right-click: a pilot, a corp, an alliance, a solar
/// system or an item type. One shared menu per kind means "Copy Name", "Open in
/// zKillboard" and friends are in the same place with the same wording on every screen.
enum EVEEntity: Hashable {
    case character(id: Int, name: String)
    case corporation(id: Int, name: String)
    case alliance(id: Int, name: String)
    case system(id: Int, name: String)
    case item(typeID: Int, name: String)

    var name: String {
        switch self {
        case .character(_, let n), .corporation(_, let n), .alliance(_, let n),
             .system(_, let n), .item(_, let n):
            return n
        }
    }

    /// zKillboard page for the entity, where zKillboard has one.
    var zKillboardURL: URL? {
        switch self {
        case .character(let id, _):   return URL(string: "https://zkillboard.com/character/\(id)/")
        case .corporation(let id, _): return URL(string: "https://zkillboard.com/corporation/\(id)/")
        case .alliance(let id, _):    return URL(string: "https://zkillboard.com/alliance/\(id)/")
        case .system(let id, _):      return URL(string: "https://zkillboard.com/system/\(id)/")
        case .item(let id, _):        return URL(string: "https://zkillboard.com/item/\(id)/")
        }
    }

    /// EVE Who for pilots/corps/alliances, DOTLAN for systems, EVE Ref for item types.
    var referenceLink: (title: LocalizedStringKey, url: URL)? {
        switch self {
        case .character(let id, _):
            return URL(string: "https://evewho.com/character/\(id)").map { ("Open in EVE Who", $0) }
        case .corporation(let id, _):
            return URL(string: "https://evewho.com/corporation/\(id)").map { ("Open in EVE Who", $0) }
        case .alliance(let id, _):
            return URL(string: "https://evewho.com/alliance/\(id)").map { ("Open in EVE Who", $0) }
        case .system(_, let name):
            let slug = name.replacingOccurrences(of: " ", with: "_")
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
            return URL(string: "https://evemaps.dotlan.net/system/\(slug)").map { ("Open in DOTLAN", $0) }
        case .item(let id, _):
            return URL(string: "https://everef.net/types/\(id)").map { ("Open in EVE Ref", $0) }
        }
    }
}

/// The shared menu items for an entity. Use directly inside an existing `.contextMenu`
/// that has screen-specific actions of its own; otherwise use `.eveContextMenu(_:)`.
struct EVEEntityMenuItems: View {
    let entity: EVEEntity
    @Environment(AccountManager.self) private var accountManager

    var body: some View {
        Button("Copy Name", systemImage: "doc.on.doc") {
            copy(entity.name)
            ToastCenter.shared.copied("“\(entity.name)”")
        }

        switch entity {
        case .system(let id, let name):
            Divider()
            Button("Set Destination", systemImage: "location.fill") {
                Task { await autopilot(systemID: id, name: name, clear: true) }
            }
            Button("Add Waypoint", systemImage: "mappin.and.ellipse") {
                Task { await autopilot(systemID: id, name: name, clear: false) }
            }
            Button("Plan Route To", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                AppRouter.shared.pendingRoute = .init(originId: nil, destinationId: id, autoPlot: false)
                AppRouter.shared.pendingSection = .routePlanner
            }
        case .item(let typeID, let name):
            Divider()
            Button("Search Market", systemImage: "cart") {
                WindowService.shared.showGalaxySearch(typeId: typeID, typeName: name)
            }
            Button("Copy Type ID", systemImage: "number") {
                copy(String(typeID))
                ToastCenter.shared.copied(String(localized: "type ID \(typeID)"))
            }
        default:
            EmptyView()
        }

        Divider()
        if let url = entity.zKillboardURL {
            Button("Open in zKillboard", systemImage: "scope") { NSWorkspace.shared.open(url) }
        }
        if let link = entity.referenceLink {
            Button(link.title, systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(link.url) }
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func autopilot(systemID: Int, name: String, clear: Bool) async {
        let result = clear
            ? await AutopilotService.setDestination(systemId: systemID, accountManager: accountManager)
            : await AutopilotService.addWaypoint(systemId: systemID, accountManager: accountManager)
        let toasts = ToastCenter.shared
        switch result {
        case .ok:
            toasts.show(clear ? String(localized: "Destination set to \(name)")
                              : String(localized: "Waypoint added: \(name)"),
                        systemImage: "location.fill")
        case .notSignedIn:
            toasts.show(String(localized: "Sign in to set a destination"), style: .failure)
        case .missingScope:
            toasts.show(String(localized: "Re-add this character to allow setting destinations"), style: .failure)
        case .failed(let message):
            toasts.show(message, style: .failure)
        }
    }
}

private struct EntityContextMenuModifier: ViewModifier {
    let entity: EVEEntity?

    func body(content: Content) -> some View {
        if let entity {
            content.contextMenu { EVEEntityMenuItems(entity: entity) }
        } else {
            content
        }
    }
}

extension View {
    /// Attaches the shared right-click menu for a character, corp, alliance, system or item.
    /// Pass `nil` to attach nothing (e.g. while an ID is still resolving).
    func eveContextMenu(_ entity: EVEEntity?) -> some View {
        modifier(EntityContextMenuModifier(entity: entity))
    }
}
