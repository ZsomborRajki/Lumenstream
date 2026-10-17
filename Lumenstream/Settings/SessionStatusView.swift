import LumenstreamData
import LumenstreamUI
import SwiftUI

/// The top of the connection sheet: what the session is doing, and the
/// actions that make sense right now.
struct SessionStatusView: View {
    @Environment(LumenstreamModel.self) private var model

    var body: some View {
        HStack {
            ConnectionStatusBadge(state: model.connectionState)
            Spacer()
            if let name = model.activeProfileName, model.connectionState.isActive {
                Text(name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }

        switch model.connectionState {
        case .disconnected:
            Text("Choose a profile below to connect.")
                .foregroundStyle(.secondary)

        case .connecting:
            Text("Opening the API socket…")
                .foregroundStyle(.secondary)

        case let .connected(version), let .brokerUnreachable(version):
            if case .brokerUnreachable = model.connectionState {
                Label("TWS lost its connection to IB. Data resumes when it reconnects.", systemImage: "icloud.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            LabeledContent("Server version", value: "\(version)")
            if let serverTime = model.serverTime {
                LabeledContent("TWS clock", value: serverTime)
            }
            if let connectedSince = model.connectedSince {
                LabeledContent("Connected") {
                    Text(connectedSince, style: .relative)
                }
            }
            if model.reconnectCount > 0 {
                LabeledContent("Reconnects", value: "\(model.reconnectCount)")
            }
            disconnectButton

        case let .reconnecting(attempt, retryAt, reason):
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
            LabeledContent("Attempt \(attempt)") {
                Text(retryAt, style: .relative)
                    .monospacedDigit()
            }
            Button("Retry Now", systemImage: "arrow.clockwise") {
                model.retryNow()
            }
            disconnectButton

        case let .failed(reason):
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if model.activeProfileName != nil {
                Button("Try Again", systemImage: "arrow.clockwise") {
                    model.retryNow()
                }
            }
        }
    }

    private var disconnectButton: some View {
        Button("Disconnect", systemImage: "xmark.circle", role: .destructive) {
            model.disconnect()
        }
    }
}

#Preview(traits: .sampleData) {
    List {
        Section {
            SessionStatusView()
        }
    }
}
