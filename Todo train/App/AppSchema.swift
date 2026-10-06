//
//  AppSchema.swift
//  Todo train
//
//  V1 はダイヤ導入前。V2 で占有・網・シリーズ。V3 で乗客の乗車。
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

enum AppSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    static var models: [any PersistentModel.Type] {
        AppSchemaV2.models + [
            PassengerRide.self,
        ]
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3]
    }

    /// 既存エンティティはそのまま。ダイヤ3型を空テーブルとして足す。
    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: AppSchemaV1.self,
        toVersion: AppSchemaV2.self,
        willMigrate: { _ in },
        didMigrate: { _ in }
    )

    /// 既存エンティティはそのまま。PassengerRide を空テーブルとして足す。
    static let migrateV2toV3 = MigrationStage.custom(
        fromVersion: AppSchemaV2.self,
        toVersion: AppSchemaV3.self,
        willMigrate: { _ in },
        didMigrate: { _ in }
    )
}
