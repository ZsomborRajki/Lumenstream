import LumenstreamData
import LumenstreamUI
import SwiftData
import SwiftUI

/// Placeholder connection sheet: lists the saved profiles and can open or close
/// a session, which is enough to smoke-test the handshake against TWS.
struct ConnectionSettingsView: View {
    @Environment(LumenstreamModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ConnectionProfile.createdAt) private var profiles: [ConnectionProfile]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ConnectionStatusBadge(state: model.connectionState)
                    if case let .failed(reason) = model.connectionState {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Profiles") {
                    ForEach(profiles) { profile in
                        Button {
                            model.connect(to: profile)
                        } label: {
                            LabeledContent(profile.name, value: "\(profile.host):\(profile.port)")
                        }
                    }
                }

                if model.connectionState != .disconnected {
                    Section {
                        Button("Disconnect", role: .destructive) {
                            model.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview(traits: .sampleData) {
    ConnectionSettingsView()
}
