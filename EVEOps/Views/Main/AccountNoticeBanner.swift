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

/// Shown above the main content when pilots were restored from backup, or when local
/// storage had to be reset. Stays until dismissed so it isn't missed on launch.
struct AccountNoticeBanner: View {
    let notice: AccountNotice
    let onDismiss: () -> Void

    private var tint: Color { notice.isWarning ? .orange : .green }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : "arrow.counterclockwise.circle.fill")
                .foregroundStyle(tint)
            Text(notice.message)
                .font(.callout)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .font(.callout)
                .buttonStyle(.plain)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10))
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.message)
    }
}
