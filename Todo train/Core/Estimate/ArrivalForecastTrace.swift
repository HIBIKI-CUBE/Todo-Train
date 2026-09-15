//
//  ArrivalForecastTrace.swift
//  Todo train
//
//  In-memory log of Hub prediction runs. Shown only after the Settings
//  hidden unlock — not a product surface.
//

import Foundation
import Observation

enum ArrivalForecastOutcome: String, Equatable, Sendable {
    case skippedNoSamples
    case heuristicOnly
    case modelUnavailable
    case parseFailed
    case modelError
    case keptMedian
    case refined

    var displayLabel: String {
        switch self {
        case .skippedNoSamples: "サンプル不足（モデルなし）"
        case .heuristicOnly: "Heuristic のみ"
        case .modelUnavailable: "モデル利用不可"
        case .parseFailed: "構造が読めない"
        case .modelError: "モデルエラー"
        case .keptMedian: "中央値のまま"
        case .refined: "分数を調整"
        }
    }
}

struct ArrivalForecastTrace: Equatable, Sendable, Identifiable {
    var id: UUID
    var recordedAt: Date
    var title: String
    var estimatedMinutes: Int?
    var hour: Int?
    var bandName: String?
    var medianMinutes: Int?
    var sampleCount: Int?
    var bandSampleCount: Int?
    var tagNames: [String]
    var recentLine: String?
    var modelAvailability: String
    var instructions: String?
    var prompt: String?
    var rawResponse: String?
    var parsedMinutes: Int?
    var clampedMinutes: Int?
    var thinking: String?
    var weightLabel: String?
    var confidenceLabel: String?
    var nativeReasoning: String?
    var outcome: ArrivalForecastOutcome
    var errorDescription: String?
    var elapsedMilliseconds: Int

    static func skipped(title: String, now: Date = .now) -> ArrivalForecastTrace {
        ArrivalForecastTrace(
            id: UUID(),
            recordedAt: now,
            title: title,
            estimatedMinutes: nil,
            hour: nil,
            bandName: nil,
            medianMinutes: nil,
            sampleCount: nil,
            bandSampleCount: nil,
            tagNames: [],
            recentLine: nil,
            modelAvailability: "—",
            instructions: nil,
            prompt: nil,
            rawResponse: nil,
            parsedMinutes: nil,
            clampedMinutes: nil,
            thinking: nil,
            weightLabel: nil,
            confidenceLabel: nil,
            nativeReasoning: nil,
            outcome: .skippedNoSamples,
            errorDescription: nil,
            elapsedMilliseconds: 0
        )
    }

    static func fromContext(
        _ context: ArrivalForecastContext,
        outcome: ArrivalForecastOutcome,
        now: Date = .now,
        modelAvailability: String,
        instructions: String? = nil,
        prompt: String? = nil,
        rawResponse: String? = nil,
        parsedMinutes: Int? = nil,
        clampedMinutes: Int? = nil,
        thinking: String? = nil,
        weightLabel: String? = nil,
        confidenceLabel: String? = nil,
        nativeReasoning: String? = nil,
        errorDescription: String? = nil,
        elapsedMilliseconds: Int = 0
    ) -> ArrivalForecastTrace {
        let recentLine = context.recent.map(ArrivalForecastPrompt.rideLine).joined(separator: "\n")
        return ArrivalForecastTrace(
            id: UUID(),
            recordedAt: now,
            title: context.title,
            estimatedMinutes: context.estimatedMinutes,
            hour: context.hour,
            bandName: context.band.promptName,
            medianMinutes: context.medianMinutes,
            sampleCount: context.sampleCount,
            bandSampleCount: context.bandSampleCount,
            tagNames: context.tagNames,
            recentLine: recentLine.isEmpty ? nil : recentLine,
            modelAvailability: modelAvailability,
            instructions: instructions,
            prompt: prompt,
            rawResponse: rawResponse,
            parsedMinutes: parsedMinutes,
            clampedMinutes: clampedMinutes,
            thinking: thinking,
            weightLabel: weightLabel,
            confidenceLabel: confidenceLabel,
            nativeReasoning: nativeReasoning,
            outcome: outcome,
            errorDescription: errorDescription,
            elapsedMilliseconds: elapsedMilliseconds
        )
    }
}

@Observable
@MainActor
final class ArrivalForecastTraceLog {
    static let shared = ArrivalForecastTraceLog()
    static let limit = 12

    private(set) var traces: [ArrivalForecastTrace] = []

    func record(_ trace: ArrivalForecastTrace) {
        traces.insert(trace, at: 0)
        if traces.count > Self.limit {
            traces = Array(traces.prefix(Self.limit))
        }
    }

    func clear() {
        traces = []
    }

    func latest(matchingTitle title: String) -> ArrivalForecastTrace? {
        traces.first { $0.title == title }
    }
}
