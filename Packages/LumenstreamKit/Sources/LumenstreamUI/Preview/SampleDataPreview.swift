import LumenstreamData
import SwiftData
import SwiftUI

/// Shares one in-memory store and a populated model across all previews.
///
/// Usage: `#Preview(traits: .sampleData) { … }`
public struct SampleDataPreview: PreviewModifier {
    public struct Context {
        let container: ModelContainer
        let model: LumenstreamModel
    }

    public init() {}

    public static func makeSharedContext() throws -> Context {
        Context(container: try LumenstreamDataContainer.make(inMemory: true), model: .preview())
    }

    public func body(content: Content, context: Context) -> some View {
        content
            .modelContainer(context.container)
            .environment(context.model)
    }
}

extension PreviewTrait where T == Preview.ViewTraits {
    @MainActor public static var sampleData: Self { .modifier(SampleDataPreview()) }
}
