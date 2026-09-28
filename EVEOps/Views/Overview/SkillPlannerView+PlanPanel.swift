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
import OSLog

extension SkillPlannerView {
    // MARK:  Plan Panel

    var planPanel: some View {
        VStack(spacing: 0) {
            if let attrs = attributes {
                attributesBar(attrs)
                    .padding(.horizontal, EVESpacing.lg)
                    .padding(.vertical, EVESpacing.md)
                    .background(EVESurface.bar)
                    .help("Estimates assume Omega clone. Alpha clone trains at 50% speed.")
                Divider()
            }

            planSummaryBar
                .padding(.horizontal, 10)
                .padding(.vertical, EVESpacing.lg)

            if let msg = importMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, EVESpacing.sm)
                    .transition(.opacity)
            }

            Divider()

            if #available(macOS 26.0, *), IntelligenceService.isSupported, let info = selectedCharInfo {
                SkillPlanAIInsightCard(characterInfo: info, onAddSkill: addPlanItem)
                    .padding(.horizontal, 10)
                    .padding(.vertical, EVESpacing.md)
                Divider()
            }

            if planItems.count > 1, let attrs = attributes {
                SkillQueueTimeline(queue: plannedQueue(attrs: attrs), tint: .eveThemeAccent,
                                   endLabel: "Plan completes", warnsWhenEndingSoon: false)
                    .padding(.horizontal, 10)
                    .padding(.vertical, EVESpacing.md)
                Divider()
            }

            if planItems.isEmpty {
                EVEEmptyState("No Skills Planned", systemImage: "list.bullet.clipboard", message: "Browse skills on the right and tap + to add them to your plan.")
            } else {
                let finishDates = planFinishDates()
                List {
                    ForEach(planItems) { item in
                        planRow(item, finish: finishDates[item.skillId])
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in
                        planItems.move(fromOffsets: from, toOffset: to)
                        savePlan()
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
            }
        }
    }

    func attributesBar(_ attrs: ESICharacterAttributes) -> some View {
        HStack(spacing: 0) {
            attrTile("INT", value: attrs.intelligence, color: .blue)
            attrTile("MEM", value: attrs.memory, color: .green)
            attrTile("PER", value: attrs.perception, color: .orange)
            attrTile("WIL", value: attrs.willpower, color: .purple)
            attrTile("CHA", value: attrs.charisma, color: .pink)
        }
    }

    func attrTile(_ label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    /// The plan laid end to end from now, as queue entries for `SkillQueueTimeline`.
    func plannedQueue(attrs: ESICharacterAttributes) -> [TrainingQueueEntry] {
        var cursor = Date()
        return planItems.enumerated().map { index, item in
            let start = cursor
            cursor = cursor.addingTimeInterval(trainingTime(for: item, attrs: attrs))
            return TrainingQueueEntry(
                position: index, skillId: item.skillId, skillName: item.skillName,
                level: item.targetLevel, startDate: start, finishDate: cursor,
                levelStartSP: nil, levelEndSP: nil, trainingStartSP: nil,
                isCurrentlyTraining: false
            )
        }
    }

    /// When each planned skill would finish if the plan started training now.
    func planFinishDates() -> [Int: Date] {
        guard let attrs = attributes else { return [:] }
        return Dictionary(plannedQueue(attrs: attrs).compactMap { entry in
            entry.finishDate.map { (entry.skillId, $0) }
        }, uniquingKeysWith: { _, last in last })
    }

    var planSummaryBar: some View {
        let totalSP = planItems.reduce(0) { $0 + spNeeded(for: $1) }
        let totalSeconds = planItems.reduce(0.0) { sum, item in
            sum + (attributes.map { attrs in trainingTime(for: item, attrs: attrs) } ?? 0)
        }
        let completes = attributes != nil && !planItems.isEmpty ? Date.now.addingTimeInterval(totalSeconds) : nil

        return VStack(spacing: EVESpacing.sm) {
            HStack(spacing: 0) {
                summaryStat("Skills") {
                    Text("\(planItems.count)")
                }
                Divider().frame(height: 30)
                summaryStat("Skill Points") {
                    Text(formatSP(totalSP))
                        .foregroundStyle(.blue)
                        .eveNumeric(totalSP)
                }
                Divider().frame(height: 30)
                summaryStat("Training Time") {
                    Text(attributes != nil ? formatDuration(totalSeconds) : "—")
                        .foregroundStyle(.green)
                }
            }
            if let completes {
                Label("Completes \(EVEDates.short(completes))", systemImage: "flag.checkered")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help(EVEDates.full(completes))
            }
        }
    }

    private func summaryStat<Value: View>(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) -> some View {
        VStack(spacing: EVESpacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            value()
                .font(.eveStatCompact)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    /// Plan actions for the window toolbar — import, export, clear, and the clipboard
    /// format help — instead of four small icons squeezed into the summary bar.
    @ViewBuilder
    var planToolbarControls: some View {
        Button {
            Task { await importFromClipboard() }
        } label: {
            if isImporting {
                ProgressView().controlSize(.small)
            } else {
                Label("Import from Clipboard", systemImage: "square.and.arrow.down")
            }
        }
        .disabled(isImporting)
        .help("Import a skill plan from the clipboard")

        Button {
            exportPlan()
        } label: {
            Label("Copy Plan", systemImage: "square.and.arrow.up")
        }
        .disabled(planItems.isEmpty)
        .help("Copy the plan to the clipboard in EVE's format")

        Button(role: .destructive) {
            let count = planItems.count
            replacePlan(with: [], actionName: String(localized: "Clear Plan"))
            ToastCenter.shared.show(String(localized: "Cleared \(count) skills — ⌘Z to undo"), systemImage: "trash.fill")
        } label: {
            Label("Clear Plan", systemImage: "trash")
        }
        .disabled(planItems.isEmpty)
        .help("Remove every skill from the plan")

        Button {
            showingClipboardHelp.toggle()
        } label: {
            Label("Clipboard Help", systemImage: "questionmark.circle")
        }
        .help("How clipboard import and export work")
        .popover(isPresented: $showingClipboardHelp, arrowEdge: .bottom) {
            clipboardHelpPopover
        }
    }

    func planRow(_ item: SkillPlanItem, finish: Date?) -> some View {
        let sp = spNeeded(for: item)
        let seconds = attributes.map { trainingTime(for: item, attrs: $0) } ?? 0.0

        return PlanRowChrome {
            HStack(spacing: EVESpacing.md) {
                CachedAsyncImage(url: EVEImageURL.typeIcon(item.skillId, size: 64)) { image in
                    image.resizable()
                } placeholder: {
                    RoundedRectangle(cornerRadius: EVERadius.xs).fill(.quaternary)
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: EVERadius.xs))

                VStack(alignment: .leading, spacing: EVESpacing.xxs) {
                    Text(item.skillName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .eveTruncationHelp(item.skillName)
                    HStack(spacing: EVESpacing.xs) {
                        levelBadge(item.fromLevel)
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        levelBadge(item.targetLevel)
                        Text(formatSP(sp))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer(minLength: EVESpacing.sm)

                VStack(alignment: .trailing, spacing: EVESpacing.xxs) {
                    if attributes != nil {
                        Text(formatDuration(seconds))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                    if let finish {
                        Text(EVEDates.short(finish))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .help("Done \(EVEDates.full(finish)) if the plan starts now")
                    }
                }
            }
        } hoverControls: {
            levelMenu(item)
            Button(role: .destructive) {
                removeFromPlan(item)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from Plan")
            .help("Remove from plan")
        }
        .contextMenu {
            levelMenuItems(item)
            Divider()
            Button("Move to Top", systemImage: "arrow.up.to.line") { move(item, toTop: true) }
                .disabled(planItems.first?.id == item.id)
            Button("Move to Bottom", systemImage: "arrow.down.to.line") { move(item, toTop: false) }
                .disabled(planItems.last?.id == item.id)
            Divider()
            EVEEntityMenuItems(entity: .item(typeID: item.skillId, name: item.skillName))
            Divider()
            Button("Remove from Plan", systemImage: "minus.circle", role: .destructive) { removeFromPlan(item) }
        }
    }

    /// Extend/Reduce choices for a plan row's target level.
    @ViewBuilder
    private func levelMenuItems(_ item: SkillPlanItem) -> some View {
        let canExtend = item.targetLevel < 5
        let canReduce = item.targetLevel > item.fromLevel + 1
        if canExtend {
            ForEach((item.targetLevel + 1)...5, id: \.self) { level in
                Button("Train to Level \(level)") { updateItem(item, targetLevel: level) }
            }
        }
        if canReduce {
            ForEach(((item.fromLevel + 1)...(item.targetLevel - 1)).reversed(), id: \.self) { level in
                Button("Stop at Level \(level)") { updateItem(item, targetLevel: level) }
            }
        }
    }

    @ViewBuilder
    private func levelMenu(_ item: SkillPlanItem) -> some View {
        if item.targetLevel < 5 || item.targetLevel > item.fromLevel + 1 {
            Menu {
                levelMenuItems(item)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel("Change Target Level")
            .help("Change target level")
        }
    }

    private func removeFromPlan(_ item: SkillPlanItem) {
        replacePlan(with: planItems.filter { $0.skillId != item.skillId },
                    actionName: String(localized: "Remove Skill"))
        ToastCenter.shared.show(String(localized: "Removed \(item.skillName) — ⌘Z to undo"), systemImage: "minus.circle.fill")
    }

    private func move(_ item: SkillPlanItem, toTop: Bool) {
        var items = planItems.filter { $0.id != item.id }
        if toTop { items.insert(item, at: 0) } else { items.append(item) }
        replacePlan(with: items, actionName: String(localized: "Move Skill"))
    }
}

/// A plan row that reveals its edit controls (level menu, remove) only on hover, so a
/// long plan doesn't show a column of red buttons. The same actions are always in the
/// row's context menu.
private struct PlanRowChrome<Content: View, Controls: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let hoverControls: () -> Controls
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: EVESpacing.sm) {
            content()
            HStack(spacing: EVESpacing.sm) {
                hoverControls()
            }
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
            .animation(.easeOut(duration: 0.12), value: isHovering)
        }
        .padding(.horizontal, EVESpacing.lg)
        .padding(.vertical, EVESpacing.sm)
        .background(isHovering ? EVEFill.subtle : Color.clear, in: RoundedRectangle(cornerRadius: EVERadius.sm))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
