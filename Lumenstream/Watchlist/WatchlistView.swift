import LumenstreamData
import LumenstreamUI
import SwiftData
import SwiftUI

struct WatchlistView: View {
    @Environment(LumenstreamModel.self) private var model
    @Query(sort: \WatchlistSymbol.sortIndex) private var symbols: [WatchlistSymbol]

    var body: some View {
        FeatureScreen(title: AppTab.watchlist.title) {
            GlassPlaceholder(
                "Streaming Quotes",
                systemImage: "list.star",
                caption: "\(resolvedCount) of \(symbols.count) symbols resolved to IB contracts. Rows will observe one Quote each (reqMktData)."
            )
            GlassPlaceholder("Symbol Detail", systemImage: "chart.xyaxis.line", caption: "Zoom transition into a chart (reqHistoricalData).")
        }
        // Resolve contract IDs whenever a session comes up.
        .task(id: model.connectionState.isConnected) {
            guard model.connectionState.isConnected else { return }
            await model.resolveContractIDs(for: symbols)
        }
    }

    private var resolvedCount: Int {
        symbols.count { $0.contractID != nil }
    }
}

#Preview(traits: .sampleData) {
    WatchlistView()
}
