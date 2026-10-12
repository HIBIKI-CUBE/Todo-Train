//
//  AppModelContainer.swift
//  Todo train
//

import CoreData
import Foundation
import SwiftData
#if os(iOS)
import SQLite3
#endif

enum AppModelContainer {
    static let schema = Schema(versionedSchema: AppSchemaV4.self)

    #if DEBUG
    /// 作り直しに落ちた回数。移行の試験は 0 のままであることを見る。
    static var rebuildCount = 0
    #endif

    // Mac は schema の版だけを読む。工場は mainContext を使うので iOS に残す。
    #if os(iOS)
    static func make(inMemory: Bool = false, storeURL: URL? = nil) throws -> ModelContainer {
        let configuration = configuration(schema: schema, inMemory: inMemory, storeURL: storeURL)
        if !inMemory {
            try relabelPostPR71StoreIfNeeded(at: configuration.url)
        }
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

    /// PR #71 は版を 3.0.0 のまま列を足した。予約列がある store は V3_1 として開く。
    private static func relabelPostPR71StoreIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        guard storeHasReservationColumn(at: url) else { return }
        var metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        let identifiers = metadata[NSStoreModelVersionIdentifiersKey] as? [String] ?? []
        guard identifiers == ["3.0.0"] else { return }
        metadata[NSStoreModelVersionIdentifiersKey] = ["3.1.0"]
        try NSPersistentStoreCoordinator.setMetadata(
            metadata,
            forPersistentStoreOfType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
    }

    private static func storeHasReservationColumn(at url: URL) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM pragma_table_info('ZTICKET') WHERE UPPER(name) = 'ZRESERVEDAT' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW
    }

    #if DEBUG
    /// 試験から作り直しだけを通す。
    static func rebuildForTesting(at storeURL: URL) throws -> ModelContainer {
        try rebuildPreservingData(after: CocoaError(.fileReadCorruptFile), storeURL: storeURL)
    }
    #endif

    /// 移行できない store は、読める版で中身を移して現行スキーマで開き直す。
    private static func rebuildPreservingData(after migrationError: Error, storeURL: URL) throws -> ModelContainer {
        #if DEBUG
        rebuildCount += 1
        #endif
        let snapshot: AppStoreSnapshot
        do {
            snapshot = try capturePreserving(at: storeURL)
        } catch {
            throw migrationError
        }
        try removeStoreFiles(at: storeURL)
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: CloudKitSync.isConfigured
                ? .private(CloudKitSync.containerIdentifier)
                : .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: AppMigrationPlan.self,
            configurations: [configuration]
        )
        snapshot.restore(into: container.mainContext)
        try container.mainContext.save()
        return container
    }

    private static func capturePreserving(at storeURL: URL) throws -> AppStoreSnapshot {
        let readers = [StoreReader.v3_1, .v3, .v2, .v1]
        var lastError: Error?
        for reader in readers {
            do {
                return try autoreleasepool {
                    let readerSchema = Schema(versionedSchema: reader.schema)
                    let configuration = ModelConfiguration(
                        schema: readerSchema,
                        url: storeURL,
                        cloudKitDatabase: .none
                    )
                    let container = try ModelContainer(for: readerSchema, configurations: [configuration])
                    return try snapshot(of: reader, from: container.mainContext)
                }
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.fileReadCorruptFile)
    }

    private enum StoreReader {
        case v3_1
        case v3
        case v2
        case v1

        var schema: any VersionedSchema.Type {
            switch self {
            case .v3_1: AppSchemaV3_1.self
            case .v3: AppSchemaV3.self
            case .v2: AppSchemaV2.self
            case .v1: AppSchemaV1.self
            }
        }
    }

    private static func snapshot(
        of reader: StoreReader,
        from context: ModelContext
    ) throws -> AppStoreSnapshot {
        switch reader {
        case .v3_1:
            try AppStoreSnapshot.captureV3_1(from: context)
        case .v3:
            try AppStoreSnapshot.captureV3(from: context)
        case .v2:
            try AppStoreSnapshot.captureV2(from: context)
        case .v1:
            try AppStoreSnapshot.captureV1(from: context)
        }
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
    #endif
}
