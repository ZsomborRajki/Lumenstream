import LumenstreamUI
import SwiftUI

struct DashboardView: View {
    var body: some View {
        FeatureScreen(title: AppTab.dashboard.title) {
            GlassPlaceholder("Net Liquidation", systemImage: "dollarsign.circle", caption: "Account summary tiles (reqAccountSummary).")
            GlassPlaceholder("Daily P&L", systemImage: "chart.line.uptrend.xyaxis", caption: "Realtime P&L stream (reqPnL).")
            GlassPlaceholder("Movers", systemImage: "flame", caption: "Top watchlist movers with sparklines.")
        }
    }
}

#Preview(traits: .sampleData) {
    DashboardView()
}
