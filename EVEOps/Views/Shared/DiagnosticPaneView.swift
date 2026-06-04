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

struct DiagnosticPaneView: View {
    @State private var selectedCategory: String? = nil
    @State private var minLevel: LogEntry.Level = .debug
    @State private var searchText = ""
    @State private var autoScroll = true
    @State private var selectedEntries: Set<LogEntry.ID> = []

    private let store = DiagnosticLogStore.shared

    private var filteredEntries: [LogEntry] {
        store.entries.filter { entry in
            (selectedCategory == nil || entry.category == selectedCategory) &&
            matchesLevelFilter(entry.level) &&
            (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText))
        }
    }

    private func matchesLevelFilter(_ level: LogEntry.Level) -> Bool {
        switch minLevel {
        case .debug:  return true
        case .info:   return level == .info
        case .notice: return level == .notice
        case .error:  return level == .error || level == .fault
        case .fault:  return level == .fault
        }
    }

    private var availableCategories: [String] {
        Array(Set(store.entries.map(\.category))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text("Diagnostic Logs")
                    .font(.largeTitle.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.background)
        }
        .navigationTitle("Diagnostic Logs")
    }

    // MARK:  Toolbar

    private var toolbar: some View {
        HStack(spacing: 6) {
            categoryChip("All", value: nil)

            ForEach(availableCategories, id: \.self) { cat in
                categoryChip(cat, value: cat)
            }

            Divider().frame(height: 14)

            Picker("Level", selection: $minLevel) {
                Text("Debug").tag(LogEntry.Level.debug)
                Text("Info").tag(LogEntry.Level.info)
                Text("Warnings").tag(LogEntry.Level.notice)
                Text("Errors").tag(LogEntry.Level.error)
            }
            .pickerStyle(.menu)
            .controlSize(.mini)
            .fixedSize()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Filter", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))

            Spacer()

            Button { autoScroll.toggle() } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(autoScroll ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Auto-scroll to latest entries")

            Button { store.clear() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear log entries")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK:  Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            List(filteredEntries, selection: $selectedEntries) { entry in
                LogEntryRow(entry: entry)
                    .id(entry.id)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .contextMenu(forSelectionType: LogEntry.ID.self) { ids in
                if !ids.isEmpty {
                    Button {
                        copyEntries(ids)
                    } label: {
                        Label(
                            ids.count == 1 ? "Copy Entry" : "Copy \(ids.count) Entries",
                            systemImage: "doc.on.doc"
                        )
                    }
                }
            } primaryAction: { _ in }
            .onChange(of: filteredEntries.count) {
                if autoScroll, let last = filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: selectedCategory) {
                if autoScroll, let last = filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: minLevel) {
                if autoScroll, let last = filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK:  Category Chip

    @ViewBuilder
    private func categoryChip(_ label: String, value: String?) -> some View {
        let isSelected = selectedCategory == value
        let color: Color = value.map(diagCategoryColor) ?? .primary
        Button {
            selectedCategory = isSelected ? nil : value
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(isSelected ? color.opacity(0.18) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(color.opacity(isSelected ? 0.55 : 0.28), lineWidth: 0.5))
                .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }

    private func copyEntries(_ ids: Set<LogEntry.ID>) {
        let lines = filteredEntries
            .filter { ids.contains($0.id) }
            .map { "\(diagTimeFormatter.string(from: $0.date))  [\($0.category)]  \($0.message)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines, forType: .string)
    }
}

// MARK:  Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 6) {
            Text(diagTimeFormatter.string(from: entry.date))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .leading)

            Text(entry.category)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(diagCategoryColor(entry.category).opacity(0.12), in: Capsule())
                .foregroundStyle(diagCategoryColor(entry.category))
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            Image(systemName: diagLevelIcon(entry.level))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(diagLevelColor(entry.level))
                .frame(width: 12)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(diagLevelColor(entry.level))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
    }
}

// MARK:  Helpers (file-private)

private let diagTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()

private func diagCategoryColor(_ category: String) -> Color {
    switch category {
    case "app":          return .green
    case "auth":         return .yellow
    case "network":      return .red
    case "prefetch":     return .teal
    case "api":          return .orange
    case "sdeData":      return .cyan
    case "dogmaEngine":  return .purple
    case "systemSearch": return .blue
    default:             return .secondary
    }
}

private func diagLevelColor(_ level: LogEntry.Level) -> Color {
    switch level {
    case .debug, .info:  return .white
    case .notice:        return .yellow
    case .error, .fault: return .red
    }
}

private func diagLevelIcon(_ level: LogEntry.Level) -> String {
    switch level {
    case .debug:   return "circle"
    case .info:    return "info.circle"
    case .notice:  return "bell.circle"
    case .error:   return "exclamationmark.triangle"
    case .fault:   return "xmark.octagon"
    }
}
