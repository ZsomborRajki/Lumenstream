import LumenstreamUI
import SwiftUI

/// Shared chrome for every top-level screen: navigation stack, ambient
/// background, scroll edge effect and the connection settings button.
struct FeatureScreen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LumenstreamTheme.spacing) {
                    content
                }
                .padding()
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .background { AmbientBackground() }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Connection", systemImage: "network") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                ConnectionSettingsView()
            }
        }
    }
}
