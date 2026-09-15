//
//  AppModelContainer.swift
//  Todo train
//

import Foundation
import SwiftData

enum AppModelContainer {
    static let schema = Schema(versionedSchema: AppSchemaV2.self)

    static func make(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration = configuration(schema: schema, inMemory: inMemory, storeURL: storeURL)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: AppMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            if inMemory { throw error }
            return try rebuildPreservingData(after: error, storeURL: configuration.url)
        }
    }

    private static func configuration(
        schema: Schema,
        inMemory: Bool,
        storeURL: URL?
    ) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        if let storeURL {
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: CloudKitSync.isConfigured
                    ? .private(CloudKitSync.containerIdentifier)
                    : .none
            )
        }
        return CloudKitSync.configuration(schema: schema, inMemory: false)
    }

    /// 未バージョンの既存 store は V1 として開ける。中身を移して V2 で開き直す。
    private static func rebuildPreservingData(after _: Error, storeURL: URL) throws -> ModelContainer {
        let snapshot: AppStoreSnapshot = try autoreleasepool {
            let v1Schema = Schema(versionedSchema: AppSchemaV1.self)
            let v1Configuration = ModelConfiguration(
                schema: v1Schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Configuration])
            return try AppStoreSnapshot.capture(from: v1Container.mainContext)
        }
        try removeStoreFiles(at: storeURL)
        let v2Configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: CloudKitSync.isConfigured
                ? .private(CloudKitSync.containerIdentifier)
                : .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [v2Configuration]
        )
        snapshot.restore(into: container.mainContext)
        try container.mainContext.save()
        return container
    }

    private static func removeStoreFiles(at url: URL) throws {
        let fileManager = FileManager.default
        let extras = [
            url,
            URL(fileURLWithPath: url.path + "-shm"),
            URL(fileURLWithPath: url.path + "-wal"),
        ]
        for extra in extras where fileManager.fileExists(atPath: extra.path) {
            try fileManager.removeItem(at: extra)
        }
    }
}
