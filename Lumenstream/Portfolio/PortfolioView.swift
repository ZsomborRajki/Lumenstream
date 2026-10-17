import LumenstreamUI
import SwiftUI

struct PortfolioView: View {
    var body: some View {
        FeatureScreen(title: AppTab.portfolio.title) {
            GlassPlaceholder(
                "Positions",
                systemImage: "chart.pie",
                caption: "Holdings with market value and unrealized P&L (reqPositions / reqAccountUpdates)."
            )
            GlassPlaceholder("Allocation", systemImage: "circle.hexagongrid", caption: "Sector and asset-class breakdown chart.")
        }
    }
}

#Preview(traits: .sampleData) {
    PortfolioView()
}
