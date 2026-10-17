import LumenstreamUI
import SwiftUI

struct SymbolSearchView: View {
    @State private var query = ""

    var body: some View {
        FeatureScreen(title: AppTab.search.title) {
            GlassPlaceholder("Symbol Search", systemImage: "magnifyingglass", caption: "Debounced matching symbols (reqMatchingSymbols), add to watchlist.")
        }
        .searchable(text: $query, prompt: "Ticker or company")
    }
}

#Preview(traits: .sampleData) {
    SymbolSearchView()
}
