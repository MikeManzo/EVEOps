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
    let emptyMessage: String
    let loadingMessage: String
    let onRetry: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        isLoading: Bool,
        error: String? = nil,
        isEmpty: Bool = false,
        emptyMessage: String = "No data available",
        loadingMessage: String = "Loading...",
        onRetry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.error = error
        self.isEmpty = isEmpty
        self.emptyMessage = emptyMessage
        self.loadingMessage = loadingMessage
        self.onRetry = onRetry
        self.content = content
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(loadingMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !apiStatus.isReachable && (error != nil || isEmpty) {
                apiUnreachableView
            } else if let error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if let onRetry {
                        Button("Retry", action: onRetry)
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(emptyMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content()
            }
        }
    }

    private var apiUnreachableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(apiStatus.statusMessage.isEmpty ? "Unable to reach EVE servers" : apiStatus.statusMessage)
                .font(.headline)
            Text("Data will refresh automatically when the connection is restored.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
