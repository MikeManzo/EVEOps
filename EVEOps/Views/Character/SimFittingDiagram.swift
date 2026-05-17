//
// SimFittingDiagram.swift
// EVEOps
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

// MARK:  Fitting Diagram

struct SimFittingDiagram: View {
    @Environment(SimulatorState.self) private var simState

    private var highSlots: [SimSlot] { simState.slots.filter { $0.category == .high } }
    private var medSlots:  [SimSlot] { simState.slots.filter { $0.category == .medium } }
    private var lowSlots:  [SimSlot] { simState.slots.filter { $0.category == .low } }
    private var rigSlots:  [SimSlot] { simState.slots.filter { $0.category == .rig } }
    private var subSlots:  [SimSlot] { simState.slots.filter { $0.category == .subsystem } }

    var body: some View {
        if simState.shipTypeId == nil {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    shipHero
                    Divider()
                    slotGrid
                        .padding(16)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "helm")
                .font(.system(size: 64))
                .foregroundStyle(.tertiary)
            Text("No Ship Selected")
                .font(.title2.bold())
                .foregroundStyle(.secondary)
            Text("Search for a ship in the left panel to begin")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var shipHero: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: EVEImageURL.typeRender(simState.shipTypeId ?? 0, size: 512)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Rectangle().fill(
                    LinearGradient(
                        colors: [Color(.darkGray).opacity(0.3), .black.opacity(0.5)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            }
            .frame(height: 200).clipped()

            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.85), location: 1)],
                startPoint: .top, endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    if simState.isLoadingShip {
                        ProgressView().tint(.white)
                    } else {
                        Text(simState.shipName)
                            .font(.title2.bold()).foregroundStyle(.white)
                        if !simState.shipClassName.isEmpty {
                            Text(simState.shipClassName)
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                Spacer()
                if simState.slots.contains(where: { !$0.isEmpty }) {
                    Button { simState.clearAll() } label: {
                        Label("Clear Fit", systemImage: "trash")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
        }
        .frame(height: 200)
    }

    private var slotGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !highSlots.isEmpty { SimSlotRowView(slots: highSlots, category: .high) }
            if !medSlots.isEmpty  { SimSlotRowView(slots: medSlots,  category: .medium) }
            if !lowSlots.isEmpty  { SimSlotRowView(slots: lowSlots,  category: .low) }
            if !rigSlots.isEmpty  { SimSlotRowView(slots: rigSlots,  category: .rig) }
            if !subSlots.isEmpty  { SimSlotRowView(slots: subSlots,  category: .subsystem) }

            if simState.slots.isEmpty && !simState.isLoadingShip {
                HStack {
                    Spacer()
                    Label("No fitting slots detected for this ship type",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.top, 20)
            }
        }
    }
}

// MARK:  Slot Row

struct SimSlotRowView: View {
    let slots: [SimSlot]
    let category: SimSlotCategory
    @Environment(SimulatorState.self) private var simState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(category.displayName, systemImage: category.icon)
                .font(.caption.bold())
                .foregroundStyle(category.color)

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(52), spacing: 6), count: 8),
                alignment: .leading,
                spacing: 6
            ) {
                ForEach(slots) { slot in
                    SimSlotSocketView(slot: slot)
                        .environment(simState)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(category.color.opacity(0.05))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(category.color.opacity(0.18), lineWidth: 1))
        )
    }
}

// MARK:  Slot Drop Target (AppKit)
// NSViewRepresentable so we can return NSDragOperation.none for incompatible slots,
// which makes the system cursor badge switch from "+" to "not-allowed" (⊘).

private final class _SimDropNSView: NSView {
    var slotCategory: SimSlotCategory = .high
    var simState: SimulatorState?
    var onTargeted: ((Bool) -> Void)?
    var onDrop: ((Int) -> Void)?

    private func dragOperation() -> NSDragOperation {
        guard let cat = simState?.draggingCategory else { return .copy }
        return cat == slotCategory ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargeted?(true)
        return dragOperation()
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dragOperation()
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargeted?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargeted?(false)
        guard let state = simState,
              let payload = state.pendingDropPayload,
              payload.category == slotCategory else {
            simState?.pendingDropPayload = nil
            return false
        }
        state.pendingDropPayload = nil
        onDrop?(payload.typeId)
        return true
    }

    // Pass mouse clicks through to the SwiftUI Button sitting on top.
    // Drag events are dispatched via NSDraggingDestination registration, not hitTest.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct SimDropTarget: NSViewRepresentable {
    let slotCategory: SimSlotCategory
    let simState: SimulatorState
    @Binding var isTargeted: Bool
    let onDrop: (Int) -> Void

    func makeNSView(context: Context) -> _SimDropNSView {
        let v = _SimDropNSView()
        v.registerForDraggedTypes([.init("public.json")])
        return v
    }

    func updateNSView(_ v: _SimDropNSView, context: Context) {
        v.slotCategory = slotCategory
        v.simState = simState
        v.onTargeted = { isTargeted = $0 }
        v.onDrop = onDrop
    }
}

// MARK:  Slot Socket

struct SimSlotSocketView: View {
    let slot: SimSlot
    @Environment(SimulatorState.self) private var simState
    @State private var showPopover = false
    @State private var isDropTargeted = false
    @State private var isHovered = false

    // Read live from simState so this view observes mutations — the `slot` let is a frozen copy.
    private var currentModuleTypeId: Int? {
        simState.slots.first { $0.id == slot.id }?.moduleTypeId
    }

    private var isActive: Bool { simState.activeSlotId == slot.id }
    private var isValidDropTarget: Bool {
        isDropTargeted && (simState.draggingCategory == nil || simState.draggingCategory == slot.category)
    }
    private var isInvalidDropTarget: Bool {
        isDropTargeted && simState.draggingCategory != nil && simState.draggingCategory != slot.category
    }
    private var isHighlighted: Bool { isActive || isValidDropTarget }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                if currentModuleTypeId == nil {
                    simState.activeSlotId = slot.id
                } else {
                    showPopover = true
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isInvalidDropTarget
                              ? Color.red.opacity(0.20)
                              : isHighlighted
                                ? slot.category.color.opacity(isDropTargeted ? 0.35 : 0.25)
                                : Color(.windowBackgroundColor).opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(
                                    isInvalidDropTarget
                                        ? Color.red.opacity(0.8)
                                        : isHighlighted ? slot.category.color : slot.category.color.opacity(0.25),
                                    lineWidth: isInvalidDropTarget || isHighlighted ? 2 : 1
                                )
                        )

                    if let typeId = currentModuleTypeId {
                        AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 64)) { img in
                            img.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                        }
                        .padding(5)
                    } else if isInvalidDropTarget {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.red.opacity(0.85))
                    } else {
                        Image(systemName: isDropTargeted ? "plus.circle.fill" : "plus")
                            .font(.system(size: isDropTargeted ? 18 : 13,
                                          weight: isDropTargeted ? .regular : .ultraLight))
                            .foregroundStyle(slot.category.color.opacity(isDropTargeted ? 0.9 : 0.35))
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 52, height: 52)
            .scaleEffect(isValidDropTarget ? 1.08 : isInvalidDropTarget ? 0.94 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isValidDropTarget)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isInvalidDropTarget)
            .background(
                SimDropTarget(
                    slotCategory: slot.category,
                    simState: simState,
                    isTargeted: $isDropTargeted
                ) { typeId in
                    guard let idx = simState.slots.firstIndex(where: { $0.id == slot.id }) else { return }
                    simState.slots[idx].moduleTypeId = typeId
                    simState.activeSlotId = nil
                    simState.draggingCategory = nil
                    simState.recomputeStats()  // immediate pass (may use fallback for new module)
                    Task {
                        // Ensure the module type is in the cache, then fetch its effect details.
                        if simState.moduleTypes[typeId] == nil {
                            let fetched = await UniverseCache.shared.types(ids: [typeId])
                            await MainActor.run {
                                if let t = fetched[typeId] {
                                    simState.moduleTypes[typeId] = t
                                    simState.recomputeStats()
                                }
                            }
                        }
                        // Now pre-fetch effect details so full dogma replaces the heuristic.
                        await MainActor.run { simState.prefetchFittedEffects() }
                    }
                }
            )
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                SimModulePopover(slot: slot)
                    .environment(simState)
            }

            // Hover × badge — shown only when a module is fitted and the slot is hovered.
            if isHovered && currentModuleTypeId != nil {
                Button {
                    simState.clearSlot(id: slot.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK:  Module Drag Preview

struct SimModuleDragPreview: View {
    let type: ESIType
    let category: SimSlotCategory

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: EVEImageURL.typeIcon(type.typeId, size: 64)) { img in
                img.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(type.name).font(.caption.bold()).lineLimit(1)
                Label(category.displayName, systemImage: category.icon)
                    .font(.caption2).foregroundStyle(category.color)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK:  Module Popover

struct SimModulePopover: View {
    let slot: SimSlot
    @Environment(SimulatorState.self) private var simState
    @Environment(\.openWindow) private var openWindow

    private var moduleType: ESIType? {
        slot.moduleTypeId.flatMap { simState.moduleTypes[$0] }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let t = moduleType, let typeId = slot.moduleTypeId {
                HStack(spacing: 12) {
                    AsyncImage(url: EVEImageURL.typeIcon(typeId, size: 128)) { img in
                        img.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 0.5))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(t.name).font(.headline).lineLimit(2)
                        Label(slot.category.displayName, systemImage: slot.category.icon)
                            .font(.caption).foregroundStyle(slot.category.color)
                    }
                    Spacer()
                }
                .padding(14)

                Divider()

                HStack(spacing: 0) {
                    Button {
                        openWindow(value: GalaxyMarketSearchInput(typeId: typeId, typeName: t.name))
                    } label: {
                        Label("Market", systemImage: "globe.europe.africa.fill")
                            .font(.caption).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.blue)

                    Divider().frame(height: 30)

                    Button(role: .destructive) {
                        simState.clearSlot(id: slot.id)
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                            .font(.caption).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless).foregroundStyle(.red)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .frame(width: 280)
    }
}
