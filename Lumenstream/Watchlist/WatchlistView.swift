import LumenstreamData
import LumenstreamUI
import SwiftData
import SwiftUI

struct WatchlistView: View {
    @Query(sort: \WatchlistSymbol.sortIndex) private var symbols: [WatchlistSymbol]

    var body: some View {
        FeatureScreen(title: AppTab.watchlist.title) {
            GlassPlaceholder(
                "Streaming Quotes",
                systemImage: "list.star",
                caption: "\(symbols.count) saved symbols. Rows will observe one Quote each (reqMktData)."
            )
            GlassPlaceholder("Symbol Detail", systemImage: "chart.xyaxis.line", caption: "Zoom transition into a chart (reqHistoricalData).")
        }
    }
}

#Preview(traits: .sampleData) {
    WatchlistView()
}
