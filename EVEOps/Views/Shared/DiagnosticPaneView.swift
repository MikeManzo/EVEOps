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
    @State private var paneHeight: CGFloat = 180
    @GestureState private var dragDelta: CGFloat = 0
    @State private var selectedCategory: String? = nil
    @State private var minLevel: LogEntry.Level = .debug
    @State private var searchText = ""
    @State private var autoScroll = true
    @AppStorage("showDiagnosticPane") private var isVisible = true

    private let store = DiagnosticLogStore.shared

    private var displayHeight: CGFloat {
        max(100, min(400, paneHeight - dragDelta))
    }

    private var filteredEntries: [LogEntry] {
        store.entries.filter { entry in
            (selectedCategory == nil || entry.category == selectedCategory) &&
            entry.level >= minLevel &&
            (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var availableCategories: [String] {
        Array(Set(store.entries.map(\.category))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            grabHandle
            toolbar
            Divider()
            logList
        }
        .frame(height: 400, alignment: .top)   // inner layout is always stable
        .frame(height: displayHeight, alignment: .top)  // only the clip boundary moves
        .clipped()
        .background(.background)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK:  Grab Handle

    private var grabHandle: some View {
        HStack {
            Spacer()
            RoundedRectangle(cornerRadius: 2)
                .fill(.secondary.opacity(0.35))
                .frame(width: 36, height: 3)
            Spacer()
        }
        .frame(height: 14)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 1)
                .updating($dragDelta) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    paneHeight = max(100, min(400, paneHeight - value.translation.height))
                }
        )
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
                Text("All").tag(LogEntry.Level.debug)
                Text("Info+").tag(LogEntry.Level.info)
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

            Button { isVisible = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide diagnostic pane")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK:  Log List

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredEntries) { entry in
                        LogEntryRow(entry: entry)
                        Divider().padding(.leading, 8).opacity(0.4)
                    }
                    Color.clear.frame(height: 1).id("diag-bottom")
                }
            }
            .onChange(of: filteredEntries.count) {
                if autoScroll { proxy.scrollTo("diag-bottom", anchor: .bottom) }
            }
            .onChange(of: selectedCategory) {
                if autoScroll { proxy.scrollTo("diag-bottom", anchor: .bottom) }
            }
            .onChange(of: minLevel) {
                if autoScroll { proxy.scrollTo("diag-bottom", anchor: .bottom) }
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
}

// MARK:  Log Entry Row

private struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 82, alignment: .leading)

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
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .contextMenu {
            Button {
                let line = "\(Self.timeFormatter.string(from: entry.date))  [\(entry.category)]  \(entry.message)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(line, forType: .string)
            } label: {
                Label("Copy Entry", systemImage: "doc.on.doc")
            }
        }
    }
}

// MARK:  Helpers (file-private)

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
    case .debug:         return .secondary
    case .info, .notice: return .primary
    case .error:         return .orange
    case .fault:         return .red
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
