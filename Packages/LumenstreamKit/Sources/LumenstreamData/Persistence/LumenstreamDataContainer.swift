import Foundation
import SwiftData
import SwiftUI

/// Version 1 of the persisted schema. New versions get their own enum and a
/// stage in ``LumenstreamMigrationPlan``.
nonisolated public enum LumenstreamSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [ConnectionProfile.self, WatchlistSymbol.self]
    }
}

nonisolated public enum LumenstreamMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [LumenstreamSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

/// Builds and seeds the app's `ModelContainer`, like Backyard Birds' data generation.
public enum LumenstreamDataContainer {
    public static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LumenstreamSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        let container = try ModelContainer(for: schema, migrationPlan: LumenstreamMigrationPlan.self, configurations: configuration)
        try seedIfNeeded(container.mainContext)
        return container
    }

    private static func seedIfNeeded(_ context: ModelContext) throws {
        if try context.fetchCount(FetchDescriptor<ConnectionProfile>()) == 0 {
            ConnectionProfile.defaults().forEach(context.insert)
        }
        if try context.fetchCount(FetchDescriptor<WatchlistSymbol>()) == 0 {
            WatchlistSymbol.defaults().forEach(context.insert)
        }
        try context.save()
    }
}

extension LumenstreamDataContainer {
    /// The on-disk container shared by every scene. Created once, on first access.
    public static let shared: ModelContainer = {
        do {
            return try make()
        } catch {
            fatalError("Failed to create the Lumenstream model container: \(error)")
        }
    }()
}

extension Scene {
    /// Attaches the shared Lumenstream `ModelContainer` to every window of the scene.
    public func lumenstreamDataContainer() -> some Scene {
        modelContainer(LumenstreamDataContainer.shared)
    }
}
