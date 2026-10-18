//
//  ReestimateRecords.swift
//  Todo train
//

import Foundation

enum ReestimateTrigger: String, Codable, Sendable {
    case checkIn
    case planEnd
    case manual
}

enum ReestimateSurface: String, Codable, Sendable {
    case iphonePortrait
    case iphoneLandscape
    case macPip
}

enum ReestimateInput: String, Codable, Sendable {
    case touch
    case click
    case keyboard
    case trackpadScroll
}

enum ReestimateDeclaration: String, Codable, Sendable {
    case recovery
    case adjust
}

enum ReestimateMode: String, Codable, Sendable {
    case progress
    case minutesOnly
    case positionReport
}

struct ReestimateEventRecord: Codable, Equatable, Sendable {
    var id: UUID
    var reestimateIndex: Int
    var trigger: ReestimateTrigger
    var surface: ReestimateSurface
    var input: ReestimateInput
    var promptId: String
    var mode: ReestimateMode
    var committedAt: Date
    var activeSeconds: Double
    var overrunSeconds: Double
    var progressAnswer: Double?
    var committedRemainingSeconds: Int
    var shownBandLowSeconds: Int?
    var shownBandHighSeconds: Int?
    var detailsOpened: Bool
    var undoneAt: Date?
    /// Mac・Watch から届いた延長の答えを受けたとき true。
    var remoteWillExtendReceived: Bool
    /// 回復運転 / 運転調整。古い記録は nil。
    var declaration: ReestimateDeclaration?
    /// 見込みの全体秒（運転調整）。古い記録は nil。
    var projectedTotalSeconds: Int?

    init(
        id: UUID = UUID(),
        reestimateIndex: Int,
        trigger: ReestimateTrigger,
        surface: ReestimateSurface,
        input: ReestimateInput,
        promptId: String,
        mode: ReestimateMode,
        committedAt: Date,
        activeSeconds: Double,
        overrunSeconds: Double,
        progressAnswer: Double?,
        committedRemainingSeconds: Int,
        shownBandLowSeconds: Int?,
        shownBandHighSeconds: Int?,
        detailsOpened: Bool,
        undoneAt: Date? = nil,
        remoteWillExtendReceived: Bool = false,
        declaration: ReestimateDeclaration? = nil,
        projectedTotalSeconds: Int? = nil
    ) {
        self.id = id
        self.reestimateIndex = reestimateIndex
        self.trigger = trigger
        self.surface = surface
        self.input = input
        self.promptId = promptId
        self.mode = mode
        self.committedAt = committedAt
        self.activeSeconds = activeSeconds
        self.overrunSeconds = overrunSeconds
        self.progressAnswer = progressAnswer
        self.committedRemainingSeconds = committedRemainingSeconds
        self.shownBandLowSeconds = shownBandLowSeconds
        self.shownBandHighSeconds = shownBandHighSeconds
        self.detailsOpened = detailsOpened
        self.undoneAt = undoneAt
        self.remoteWillExtendReceived = remoteWillExtendReceived
        self.declaration = declaration
        self.projectedTotalSeconds = projectedTotalSeconds
    }
}

enum ReestimatePromptID {
    static let progressV1 = "reestimate.progress.v1"
    static let remainingV1 = "reestimate.remaining.v1"
    static let positionV1 = "reestimate.position.v1"
}
