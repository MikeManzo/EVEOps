import SwiftUI

struct LoadingStateView<Content: View>: View {
    @Environment(APIStatusMonitor.self) private var apiStatus

    let isLoading: Bool
    let error: String?
    let isEmpty: Bool
    let emptyMessage: String
    @ViewBuilder let content: () -> Content

    init(
        isLoading: Bool,
        error: String? = nil,
        isEmpty: Bool = false,
        emptyMessage: String = "No data available",
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.error = error
        self.isEmpty = isEmpty
        self.emptyMessage = emptyMessage
        self.content = content
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading...")
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
