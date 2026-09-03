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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)
                    .help("Estimates assume Omega clone. Alpha clone trains at 50% speed.")
                Divider()
            }

            planSummaryBar
                .padding(10)

            if let msg = importMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
                    .transition(.opacity)
            }

            Divider()

            if #available(macOS 26.0, *), IntelligenceService.isSupported, let info = selectedCharInfo {
                SkillPlanAIInsightCard(characterInfo: info, onAddSkill: addPlanItem)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                Divider()
            }

            if planItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text("No skills planned")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text("Browse skills on the right and tap + to add them to your plan.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(planItems) { item in
                        planRow(item)
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

    var planSummaryBar: some View {
        let totalSP = planItems.reduce(0) { $0 + spNeeded(for: $1) }
        let totalSeconds = planItems.reduce(0.0) { sum, item in
            sum + (attributes.map { attrs in trainingTime(for: item, attrs: attrs) } ?? 0)
        }

        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                Text("Skills")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(planItems.count)")
                    .font(.title3.bold())
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Total SP")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatSP(totalSP))
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.blue)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            VStack(spacing: 2) {
                Text("Time")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(attributes != nil ? formatDuration(totalSeconds) : "—")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 30)

            HStack(spacing: 12) {
                Button {
                    showingClipboardHelp.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("How to use clipboard import/export")
                .popover(isPresented: $showingClipboardHelp, arrowEdge: .bottom) {
                    clipboardHelpPopover
                }

                Button {
                    exportPlan()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(planItems.isEmpty ? Color.secondary : Color.primary)
                }
                .buttonStyle(.plain)
                .disabled(planItems.isEmpty)
                .help("Copy plan to clipboard (EVE-compatible format)")

                Button {
                    Task { await importFromClipboard() }
                } label: {
                    if isImporting {
                        ProgressView().controlSize(.mini).frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .help("Import plan from clipboard")

                Button(role: .destructive) {
                    planItems.removeAll()
                    savePlan()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(planItems.isEmpty ? Color.secondary : Color.red)
                }
                .buttonStyle(.plain)
                .disabled(planItems.isEmpty)
            }
            .padding(.horizontal, 10)
        }
    }

    func planRow(_ item: SkillPlanItem) -> some View {
        let sp = spNeeded(for: item)
        let seconds = attributes.map { trainingTime(for: item, attrs: $0) } ?? 0.0

        return HStack(spacing: 8) {
            CachedAsyncImage(url: EVEImageURL.typeIcon(item.skillId, size: 64)) { phase in
                if let image = phase.image {
                    image.resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 28, height: 28)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.skillName)
                    .font(.caption.bold())
                    .lineLimit(1)
                HStack(spacing: 4) {
                    levelBadge(item.fromLevel)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    levelBadge(item.targetLevel)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatSP(sp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if attributes != nil {
                    Text(formatDuration(seconds))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            if item.fromLevel < 4 {
                let canExtend = item.targetLevel < 5
                let canReduce = item.targetLevel > item.fromLevel + 1
                if canExtend || canReduce {
                    Menu {
                        if canExtend {
                            ForEach((item.targetLevel + 1)...5, id: \.self) { level in
                                Button("Extend to L\(level)") { updateItem(item, targetLevel: level) }
                            }
                        }
                        if canExtend && canReduce { Divider() }
                        if canReduce {
                            ForEach(((item.fromLevel + 1)...(item.targetLevel - 1)).reversed(), id: \.self) { level in
                                Button("Reduce to L\(level)") { updateItem(item, targetLevel: level) }
                            }
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                }
            }

            Button(role: .destructive) {
                planItems.removeAll { $0.skillId == item.skillId }
                savePlan()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

}
