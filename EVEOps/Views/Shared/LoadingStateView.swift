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

struct LoadingStateView<Content: View>: View {
    @Environment(APIStatusMonitor.self) private var apiStatus

    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    /// When true, cached/previous content is already available: stay on it and
    /// show only a thin top progress strip while refreshing, instead of a
    /// full-screen spinner (stale-while-revalidate). Errors and empty states are
    /// then the caller's responsibility to surface inline.
    let hasContent: Bool
    let emptyMessage: String
    let loadingMessage: String
    /// Show a redacted skeleton instead of a centered spinner on cold load.
    let showsSkeleton: Bool
    let onRetry: (() -> Void)?
    /// Optional clickable link shown below the error text (e.g. a manual fix-it page the
    /// generic retry action can't reach). Rendered only when both label and URL are set.
    let errorLinkLabel: String?
    let errorLinkURL: URL?
    @ViewBuilder let content: () -> Content

    init(
        isLoading: Bool,
        error: String? = nil,
        isEmpty: Bool = false,
        hasContent: Bool = false,
        emptyMessage: String = "No data available",
        loadingMessage: String = "Loading...",
        showsSkeleton: Bool = false,
        onRetry: (() -> Void)? = nil,
        errorLinkLabel: String? = nil,
        errorLinkURL: URL? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.error = error
        self.isEmpty = isEmpty
        self.hasContent = hasContent
        self.emptyMessage = emptyMessage
        self.loadingMessage = loadingMessage
        self.showsSkeleton = showsSkeleton
        self.onRetry = onRetry
        self.errorLinkLabel = errorLinkLabel
        self.errorLinkURL = errorLinkURL
        self.content = content
    }

    var body: some View {
        Group {
            if isLoading && hasContent {
                // Stale-while-revalidate: keep showing what we have.
                content()
                    .overlay(alignment: .top) { refreshingStrip }
            } else if isLoading {
                if showsSkeleton {
                    LoadingSkeleton()
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(loadingMessage)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(loadingMessage)
                }
            } else if !apiStatus.isReachable && (error != nil || isEmpty) {
                apiUnreachableView
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if let errorLinkLabel, let errorLinkURL {
                        Link(errorLinkLabel, destination: errorLinkURL)
                            .font(.caption)
                    }
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Error: \(error)")
            } else if isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(emptyMessage)
            } else {
                content()
            }
        }
    }

    private var refreshingStrip: some View {
        ProgressView()
            .progressViewStyle(.linear)
            .tint(.accentColor)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
            .accessibilityLabel("Refreshing")
    }

    private var apiUnreachableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(apiStatus.statusMessage.isEmpty ? "Unable to reach EVE servers" : apiStatus.statusMessage)
                .font(.headline)
            Text("Data will refresh automatically when the connection is restored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
