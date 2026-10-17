import LumenstreamData
import SwiftUI

/// A compact glass capsule summarizing the TWS session state.
public struct ConnectionStatusBadge: View {
    private let state: ConnectionState

    public init(state: ConnectionState) {
        self.state = state
    }

    public var body: some View {
        Label {
            Text(title)
                .contentTransition(.interpolate)
        } icon: {
            Image(systemName: symbol)
                .symbolEffect(.pulse, isActive: state == .connecting)
                .contentTransition(.symbolEffect(.replace))
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(tint.opacity(0.35)), in: .capsule)
        .animation(.smooth, value: state)
    }

    private var title: LocalizedStringKey {
        switch state {
        case .disconnected: "Offline"
        case .connecting: "Connecting"
        case let .connected(version): "Live · v\(version)"
        case .failed: "Failed"
        }
    }

    private var symbol: String {
        switch state {
        case .disconnected: "bolt.horizontal.circle"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .connected: "bolt.horizontal.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .disconnected: .gray
        case .connecting: .yellow
        case .connected: .green
        case .failed: .red
        }
    }
}

#Preview {
    VStack {
        ConnectionStatusBadge(state: .disconnected)
        ConnectionStatusBadge(state: .connecting)
        ConnectionStatusBadge(state: .connected(serverVersion: 176))
        ConnectionStatusBadge(state: .failed("Refused"))
    }
    .padding()
    .background(AmbientBackground())
}
