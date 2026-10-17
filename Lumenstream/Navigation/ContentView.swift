//
//  ContentView.swift
//  Lumenstream
//
//  Created by Zsombor Rajki on 2026. 10. 17..
//

import LumenstreamData
import LumenstreamUI
import SwiftUI

/// The root tab structure. Becomes a sidebar on iPad and collapses into a
/// minimized Liquid Glass tab bar while scrolling on iPhone.
struct ContentView: View {
    @State private var selection: AppTab = .dashboard

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.dashboard.title, systemImage: AppTab.dashboard.systemImage, value: .dashboard) {
                DashboardView()
            }
            Tab(AppTab.watchlist.title, systemImage: AppTab.watchlist.systemImage, value: .watchlist) {
                WatchlistView()
            }
            Tab(AppTab.portfolio.title, systemImage: AppTab.portfolio.systemImage, value: .portfolio) {
                PortfolioView()
            }
            Tab(AppTab.activity.title, systemImage: AppTab.activity.systemImage, value: .activity) {
                ActivityView()
            }
            Tab(value: .search, role: .search) {
                SymbolSearchView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            ConnectionAccessory()
        }
    }
}

#Preview(traits: .sampleData) {
    ContentView()
}
