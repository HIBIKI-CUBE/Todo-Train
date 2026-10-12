//
//  AppSchema.swift
//  Todo train
//
//  V1 はダイヤ導入前。V2 で占有・網・シリーズ。V3 で乗客の乗車。
//  V3 は PR #71 より前の列で凍結する。PR #71 の列は V3_1（3.1.0）。
//

import Foundation
import SwiftData

enum AppSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            AppSchemaV3.Ticket.self,
            AppSchemaV3.WorkSession.self,
            AppSchemaV3.SessionExtension.self,
            AppSchemaV3.SessionPause.self,
            AppSchemaV3.Tag.self,
            AppSchemaV3.TaskLineage.self,
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

    @Model
    final class Ticket {
        var id: UUID = UUID()
        var title: String = ""
        var estimatedSeconds: Int = 0
        var sortOrder: Int = 0
        var createdAt: Date = Date.now
        var dueDate: Date?
        var closedAt: Date?
        var closureKindRaw: String?
        var tags: [Tag] = []

        @Relationship(deleteRule: .cascade, inverse: \WorkSession.ticket)
        var sessions: [WorkSession] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskLineage.parent)
        var childLineages: [TaskLineage] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskLineage.child)
        var parentLineages: [TaskLineage] = []

        init(
            id: UUID = UUID(),
            title: String,
            estimatedSeconds: Int,
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.estimatedSeconds = min(max(estimatedSeconds, 0), 3600)
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class WorkSession {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var segmentStartedAt: Date?
        var pausedAt: Date?
        var accumulatedActiveSeconds: TimeInterval = 0
        var estimatedSecondsAtStart: Int = 0
        var budgetSecondsAtStart: Int = 0
        var outcomeRaw: String?
        var overtimeResolutionRaw: String?
        var checkInOffsetSeconds: [Double] = []
        var checkInFiredCount: Int = 0
        var pendingCheckInKindRaw: String?
        var checkInPromptLine: String?
        var checkInAnswersJSON: String = "[]"
        var awayDueAt: Date?
        var boardedDeviceID: String?
        var timetableHeld: Bool = false
        var ticket: Ticket?

        @Relationship(deleteRule: .cascade, inverse: \SessionExtension.session)
        var extensions: [SessionExtension] = []

        @Relationship(deleteRule: .cascade, inverse: \SessionPause.session)
        var pauses: [SessionPause] = []

        init(
            id: UUID = UUID(),
            startedAt: Date,
            estimatedSecondsAtStart: Int,
            ticket: Ticket? = nil,
            boardedDeviceID: String? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = nil
            self.segmentStartedAt = startedAt
            self.pausedAt = nil
            self.accumulatedActiveSeconds = 0
            self.estimatedSecondsAtStart = estimatedSecondsAtStart
            self.budgetSecondsAtStart = estimatedSecondsAtStart
            self.outcomeRaw = nil
            self.overtimeResolutionRaw = nil
            self.checkInOffsetSeconds = []
            self.checkInFiredCount = 0
            self.pendingCheckInKindRaw = nil
            self.checkInPromptLine = nil
            self.checkInAnswersJSON = "[]"
            self.awayDueAt = nil
            self.boardedDeviceID = boardedDeviceID
            self.timetableHeld = false
            self.ticket = ticket
        }
    }

    @Model
    final class SessionExtension {
        var id: UUID = UUID()
        var addedSeconds: Int = 0
        var reason: String?
        var createdAt: Date = Date.now
        var session: WorkSession?

        init(
            id: UUID = UUID(),
            addedSeconds: Int,
            reason: String? = nil,
            createdAt: Date = .now,
            session: WorkSession? = nil
        ) {
            self.id = id
            self.addedSeconds = max(0, addedSeconds)
            self.reason = reason
            self.createdAt = createdAt
            self.session = session
        }
    }

    @Model
    final class SessionPause {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var session: WorkSession?

        init(
            id: UUID = UUID(),
            startedAt: Date = .now,
            endedAt: Date? = nil,
            session: WorkSession? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.session = session
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#888888"
        var sortOrder: Int = 0
        var createdAt: Date = Date.now

        @Relationship(inverse: \Ticket.tags)
        var tickets: [Ticket] = []

        init(
            id: UUID = UUID(),
            name: String,
            colorHex: String = "#888888",
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class TaskLineage {
        var id: UUID = UUID()
        var kindRaw: String = "manual"
        var createdAt: Date = Date.now
        var fromSessionID: UUID?
        var aiGenerated: Bool = false
        var parent: Ticket?
        var child: Ticket?

        init(
            id: UUID = UUID(),
            kindRaw: String,
            parent: Ticket?,
            child: Ticket?,
            createdAt: Date = .now,
            fromSessionID: UUID? = nil,
            aiGenerated: Bool = false
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.createdAt = createdAt
            self.fromSessionID = fromSessionID
            self.aiGenerated = aiGenerated
            self.parent = parent
            self.child = child
        }
    }
}

/// PR #71 のビルドが版 3.0.0 のまま書いた形。予約と検札の列がある。
enum AppSchemaV3_1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(3, 1, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Ticket.self,
            WorkSession.self,
            SessionExtension.self,
            SessionPause.self,
            Tag.self,
            TaskLineage.self,
            ServiceDay.self,
            TimetableBlock.self,
            TimetableGuard.self,
            TimetableSeriesRule.self,
            PassengerRide.self,
        ]
    }

    @Model
    final class Ticket {
        var id: UUID = UUID()
        var title: String = ""
        var estimatedSeconds: Int = 0
        var sortOrder: Int = 0
        var createdAt: Date = Date.now
        var dueDate: Date?
        var closedAt: Date?
        var closureKindRaw: String?
        var reservedAt: Date?
        var reservedFromRideId: UUID?
        var reservedViaRaw: String?
        var tags: [Tag] = []

        @Relationship(deleteRule: .cascade, inverse: \WorkSession.ticket)
        var sessions: [WorkSession] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskLineage.parent)
        var childLineages: [TaskLineage] = []

        @Relationship(deleteRule: .nullify, inverse: \TaskLineage.child)
        var parentLineages: [TaskLineage] = []

        init(
            id: UUID = UUID(),
            title: String,
            estimatedSeconds: Int,
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.estimatedSeconds = min(max(estimatedSeconds, 0), 3600)
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class WorkSession {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var segmentStartedAt: Date?
        var pausedAt: Date?
        var accumulatedActiveSeconds: TimeInterval = 0
        var estimatedSecondsAtStart: Int = 0
        var budgetSecondsAtStart: Int = 0
        var outcomeRaw: String?
        var overtimeResolutionRaw: String?
        var arrivalActionRaw: String?
        var arrivalStampedAt: Date?
        var startedFromRaw: String = RideStartOrigin.other.rawValue
        var checkInOffsetSeconds: [Double] = []
        var checkInFiredCount: Int = 0
        var pendingCheckInKindRaw: String?
        var checkInPromptLine: String?
        var checkInAnswersJSON: String = "[]"
        var awayDueAt: Date?
        var boardedDeviceID: String?
        var timetableHeld: Bool = false
        var ticket: Ticket?

        @Relationship(deleteRule: .cascade, inverse: \SessionExtension.session)
        var extensions: [SessionExtension] = []

        @Relationship(deleteRule: .cascade, inverse: \SessionPause.session)
        var pauses: [SessionPause] = []

        init(
            id: UUID = UUID(),
            startedAt: Date,
            estimatedSecondsAtStart: Int,
            ticket: Ticket? = nil,
            boardedDeviceID: String? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.segmentStartedAt = startedAt
            self.estimatedSecondsAtStart = estimatedSecondsAtStart
            self.budgetSecondsAtStart = estimatedSecondsAtStart
            self.boardedDeviceID = boardedDeviceID
            self.ticket = ticket
        }
    }

    @Model
    final class SessionExtension {
        var id: UUID = UUID()
        var addedSeconds: Int = 0
        var reason: String?
        var createdAt: Date = Date.now
        var session: WorkSession?

        init(
            id: UUID = UUID(),
            addedSeconds: Int,
            reason: String? = nil,
            createdAt: Date = .now,
            session: WorkSession? = nil
        ) {
            self.id = id
            self.addedSeconds = max(0, addedSeconds)
            self.reason = reason
            self.createdAt = createdAt
            self.session = session
        }
    }

    @Model
    final class SessionPause {
        var id: UUID = UUID()
        var startedAt: Date = Date.now
        var endedAt: Date?
        var session: WorkSession?

        init(
            id: UUID = UUID(),
            startedAt: Date = .now,
            endedAt: Date? = nil,
            session: WorkSession? = nil
        ) {
            self.id = id
            self.startedAt = startedAt
            self.endedAt = endedAt
            self.session = session
        }
    }

    @Model
    final class Tag {
        var id: UUID = UUID()
        var name: String = ""
        var colorHex: String = "#888888"
        var sortOrder: Int = 0
        var createdAt: Date = Date.now

        @Relationship(inverse: \Ticket.tags)
        var tickets: [Ticket] = []

        init(
            id: UUID = UUID(),
            name: String,
            colorHex: String = "#888888",
            sortOrder: Int = 0,
            createdAt: Date = .now
        ) {
            self.id = id
            self.name = name
            self.colorHex = colorHex
            self.sortOrder = sortOrder
            self.createdAt = createdAt
        }
    }

    @Model
    final class TaskLineage {
        var id: UUID = UUID()
        var kindRaw: String = "manual"
        var createdAt: Date = Date.now
        var fromSessionID: UUID?
        var aiGenerated: Bool = false
        var parent: Ticket?
        var child: Ticket?

        init(
            id: UUID = UUID(),
            kindRaw: String,
            parent: Ticket?,
            child: Ticket?,
            createdAt: Date = .now,
            fromSessionID: UUID? = nil,
            aiGenerated: Bool = false
        ) {
            self.id = id
            self.kindRaw = kindRaw
            self.createdAt = createdAt
            self.fromSessionID = fromSessionID
            self.aiGenerated = aiGenerated
            self.parent = parent
            self.child = child
        }
    }
}

enum AppMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            AppSchemaV1.self,
            AppSchemaV2.self,
            AppSchemaV3.self,
        ]
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
