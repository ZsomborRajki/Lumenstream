import LumenstreamData
import LumenstreamUI
import SwiftData
import SwiftUI

/// What the profile editor is working on.
enum ProfileEditorTarget: Identifiable {
    case new
    case existing(ConnectionProfile)

    var id: String {
        switch self {
        case .new: "new"
        case let .existing(profile): "\(profile.persistentModelID.hashValue)"
        }
    }
}

/// A default TWS / IB Gateway socket port.
private struct PortPreset {
    let label: String
    let port: Int
    let isPaper: Bool
}

/// Creates or edits a ``ConnectionProfile``. Edits go to a draft and are only
/// written on Save, so cancelling leaves the stored profile untouched.
struct ProfileEditor: View {
    let target: ProfileEditorTarget
    /// Names already taken. Profile names are unique, and inserting a duplicate
    /// would silently overwrite the existing profile.
    let existingNames: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = "127.0.0.1"
    @State private var port = 7497
    @State private var clientID = 1
    @State private var isPaperTrading = true

    /// IB's default socket ports.
    private static let presets = [
        PortPreset(label: "TWS Paper", port: 7497, isPaper: true),
        PortPreset(label: "TWS Live", port: 7496, isPaper: false),
        PortPreset(label: "Gateway Paper", port: 4002, isPaper: true),
        PortPreset(label: "Gateway Live", port: 4001, isPaper: false),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Host", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                    Stepper(value: $clientID, in: 0...999) {
                        LabeledContent("Client ID", value: "\(clientID)")
                    }
                    Toggle("Paper Trading", isOn: $isPaperTrading)
                } footer: {
                    if let problem {
                        Text(problem)
                            .foregroundStyle(.red)
                    } else {
                        Text("Each app connected to the same TWS needs its own client ID.")
                    }
                }

                Section("Default Ports") {
                    ForEach(Self.presets, id: \.port) { preset in
                        Button {
                            port = preset.port
                            isPaperTrading = preset.isPaper
                        } label: {
                            LabeledContent(preset.label, value: "\(preset.port)")
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle(isNew ? "New Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", role: .confirm) {
                        save()
                        dismiss()
                    }
                    .disabled(problem != nil)
                }
            }
            .onAppear(perform: loadDraft)
        }
    }

    private var isNew: Bool {
        if case .new = target { true } else { false }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }

    /// Why the draft can't be saved, if anything.
    private var problem: String? {
        var takenNames = existingNames
        if case let .existing(profile) = target { takenNames.remove(profile.name) }

        if trimmedName.isEmpty { return "Enter a name." }
        if takenNames.contains(trimmedName) { return "A profile named “\(trimmedName)” already exists." }
        if trimmedHost.isEmpty { return "Enter the host running TWS or IB Gateway." }
        if !(1...65535).contains(port) { return "Ports range from 1 to 65535." }
        return nil
    }

    private func loadDraft() {
        guard case let .existing(profile) = target else { return }
        name = profile.name
        host = profile.host
        port = profile.port
        clientID = profile.clientID
        isPaperTrading = profile.isPaperTrading
    }

    private func save() {
        switch target {
        case .new:
            modelContext.insert(ConnectionProfile(name: trimmedName, host: trimmedHost, port: port, clientID: clientID, isPaperTrading: isPaperTrading))
        case let .existing(profile):
            profile.name = trimmedName
            profile.host = trimmedHost
            profile.port = port
            profile.clientID = clientID
            profile.isPaperTrading = isPaperTrading
        }
    }
}

#Preview(traits: .sampleData) {
    ProfileEditor(target: .new, existingNames: ["TWS Paper"])
}
