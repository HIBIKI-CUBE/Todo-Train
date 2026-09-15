//
//  AppSchema.swift
//  Todo train
//
//  V1 はダイヤ導入前。V2 で占有・網・シリーズを足す。
//

import Foundation
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Ticket.self,
            WorkSession.self,
            SessionExtension.self,
            SessionPause.self,
            Tag.self,
            TaskLineage.self,
            ServiceDay.self,
        ]
    }
}

enum AppSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    static var models: [any PersistentModel.Type] {
        AppSchemaV1.models + [
            TimetableBlock.self,
            TimetableGuard.self,
            TimetableSeriesRule.self,
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    /// 既存エンティティはそのまま。ダイヤ3型を空テーブルとして足す。
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self,
        willMigrate: { _ in },
        didMigrate: { _ in }
    )
}
