/// Top-level destinations, in the spirit of Food Truck's `Panel`.
enum AppTab: Hashable, CaseIterable {
    case dashboard
    case watchlist
    case portfolio
    case activity
    case search

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .watchlist: "Watchlist"
        case .portfolio: "Portfolio"
        case .activity: "Activity"
        case .search: "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .watchlist: "list.star"
        case .portfolio: "chart.pie"
        case .activity: "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case .search: "magnifyingglass"
        }
    }
}
