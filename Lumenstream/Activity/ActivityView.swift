import LumenstreamData
import LumenstreamUI
import SwiftUI

struct ActivityView: View {
    @Environment(LumenstreamModel.self) private var model

    var body: some View {
        FeatureScreen(title: AppTab.activity.title) {
            GlassPlaceholder("Executions", systemImage: "checkmark.seal", caption: "Today's fills and open orders, read-only (reqExecutions / reqOpenOrders).")
            NoticeLogCard(notices: model.notices)
        }
    }
}

/// The session's TWS notices, newest first.
private struct NoticeLogCard: View {
    let notices: [ServerNotice]

    /// Enough to scan; the model keeps up to 200.
    private static let visibleLimit = 20

    var body: some View {
        VStack(alignment: .leading, spacing: LumenstreamTheme.spacing) {
            Label("Server Notices", systemImage: "bell.badge")
                .font(.headline)
            if notices.isEmpty {
                Text("Errors and status messages from TWS appear here once connected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(notices.prefix(Self.visibleLimit)) { notice in
                    NoticeRow(notice: notice)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LumenstreamTheme.spacing)
        .glassEffect(.regular, in: .rect(cornerRadius: LumenstreamTheme.cornerRadius))
    }
}

#Preview(traits: .sampleData) {
    ActivityView()
}
