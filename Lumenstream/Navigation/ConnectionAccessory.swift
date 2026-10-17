import LumenstreamData
import LumenstreamUI
import SwiftUI

/// Lives in the tab view's bottom accessory slot: always-visible session status.
struct ConnectionAccessory: View {
    @Environment(LumenstreamModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack {
            ConnectionStatusBadge(state: model.connectionState)
            if placement != .inline, let account = model.selectedAccount {
                Spacer()
                Text(account)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
    }
}
