import SwiftUI

/// A Liquid Glass card standing in for a feature that hasn't been built yet.
public struct GlassPlaceholder: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let caption: LocalizedStringKey

    public init(_ title: LocalizedStringKey, systemImage: String, caption: LocalizedStringKey) {
        self.title = title
        self.systemImage = systemImage
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: LumenstreamTheme.compactSpacing) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LumenstreamTheme.spacing)
        .glassEffect(.regular, in: .rect(cornerRadius: LumenstreamTheme.cornerRadius))
    }
}

#Preview {
    ZStack {
        AmbientBackground()
        GlassPlaceholder("Watchlist", systemImage: "list.star", caption: "Streaming quotes land here.")
            .padding()
    }
}
