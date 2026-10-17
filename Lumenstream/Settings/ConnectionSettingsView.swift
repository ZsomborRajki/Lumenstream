import LumenstreamData
import LumenstreamUI
import SwiftData
import SwiftUI

/// The connection sheet: live session status, account choice, saved profiles
/// and the latest TWS notices.
struct ConnectionSettingsView: View {
    @Environment(LumenstreamModel.self) private var model
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ConnectionProfile.createdAt) private var profiles: [ConnectionProfile]

    @State private var editorTarget: ProfileEditorTarget?

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                Section {
                    SessionStatusView()
                }

                if model.accounts.count > 1 {
                    Section("Account") {
                        Picker("Account", selection: $model.selectedAccount) {
                            ForEach(model.accounts, id: \.self) { account in
                                Text(account)
                                    .monospaced()
                                    .tag(Optional(account))
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }

                Section {
                    ForEach(profiles) { profile in
                        profileRow(profile)
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("""
                        In TWS, open Settings › API › Settings, enable socket clients and Read-Only API, \
                        and add this device's IP address to Trusted IPs. The simulator connects as 127.0.0.1.
                        """)
                }

                if !model.notices.isEmpty {
                    Section("Recent Notices") {
                        ForEach(model.notices.prefix(5)) { notice in
                            NoticeRow(notice: notice)
                        }
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add Profile", systemImage: "plus") {
                        editorTarget = .new
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark", role: .confirm) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                ProfileEditor(target: target, existingNames: Set(profiles.map(\.name)))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func profileRow(_ profile: ConnectionProfile) -> some View {
        let isActive = profile.persistentModelID == model.activeProfileID && model.connectionState.isActive
        return Button {
            model.connect(to: profile)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .foregroundStyle(.primary)
                    Text(verbatim: "\(profile.host):\(profile.port) · client \(profile.clientID)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(profile.isPaperTrading ? "Paper" : "Live")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .glassEffect(.regular.tint((profile.isPaperTrading ? Color.blue : .orange).opacity(0.35)), in: .capsule)
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Active")
                }
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(profile)
            }
            .disabled(isActive)
            Button("Edit", systemImage: "pencil") {
                editorTarget = .existing(profile)
            }
        }
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                editorTarget = .existing(profile)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                modelContext.delete(profile)
            }
            .disabled(isActive)
        }
    }
}

#Preview(traits: .sampleData) {
    ConnectionSettingsView()
}
