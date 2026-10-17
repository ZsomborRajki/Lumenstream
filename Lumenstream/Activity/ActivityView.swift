import LumenstreamData
import LumenstreamUI
import SwiftUI

struct ActivityView: View {
    @Environment(LumenstreamModel.self) private var model

    var body: some View {
        FeatureScreen(title: AppTab.activity.title) {
            GlassPlaceholder("Executions", systemImage: "checkmark.seal", caption: "Today's fills and open orders, read-only (reqExecutions / reqOpenOrders).")
            GlassPlaceholder(
                "Server Notices",
                systemImage: "bell.badge",
                caption: "\(model.notices.count) notices received this session."
            )
        }
    }
}

#Preview(traits: .sampleData) {
    ActivityView()
}
