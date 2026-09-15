//
//  ArrivalForecast.swift
//  Todo train
//
//  Heuristic skeleton for Hub arrival prediction. On-device model may
//  refine minutes from structured output; it does not replace the median
//  and never coaches.
//

import Foundation

enum WorkHourBand: String, Equatable, Sendable {
    case night
    case morning
    case afternoon
    case evening

    var promptName: String {
        switch self {
        case .night: "深夜"
        case .morning: "朝"
        case .afternoon: "昼"
        case .evening: "夜"
        }
    }

    static func of(hour: Int) -> WorkHourBand {
        switch hour {
        case 5..<11: .morning
        case 11..<17: .afternoon
        case 17..<22: .evening
        default: .night
        }
    }
}

enum ArrivalForecastWeight: String, Equatable, Sendable {
    case lighter
    case similar
    case heavier

    var displayLabel: String {
        switch self {
        case .lighter: "軽め"
        case .similar: "同程度"
        case .heavier: "重め"
        }
    }
}

enum ArrivalForecastConfidence: String, Equatable, Sendable {
    case low
    case medium
    case high

    var displayLabel: String {
        switch self {
        case .low: "低"
        case .medium: "中"
        case .high: "高"
        }
    }
}

/// Structured model output. Hub uses resolved minutes only.
struct ArrivalForecastDraft: Equatable, Sendable {
    var thinking: String
    var predictedMinutes: Int
    var weight: ArrivalForecastWeight
    var confidence: ArrivalForecastConfidence

    var debugDump: String {
        """
        thinking: \(thinking)
        predictedMinutes: \(predictedMinutes)
        weight: \(weight.rawValue)
        confidence: \(confidence.rawValue)
        """
    }
}

struct ArrivalForecastContext: Equatable, Sendable {
    struct RideRecord: Equatable, Sendable {
        var title: String
        var startedLabel: String
        var estimatedMinutes: Int
        var actualMinutes: Int
        var budgetMinutes: Int
        var extensionMinutes: Int
        var extensionReasons: [String]
        var punctuality: ArrivalPunctuality
    }

    var title: String
    var tagNames: [String]
    var estimatedMinutes: Int
    var nowLabel: String
    var hour: Int
    var band: WorkHourBand
    var medianMinutes: Int
    var sampleCount: Int
    var bandSampleCount: Int
    var earlyCount: Int
    var onTimeCount: Int
    var lateCount: Int
    var extendedCount: Int
    var recent: [RideRecord]

    var fingerprint: ArrivalForecastFingerprint {
        ArrivalForecastFingerprint(self)
    }
}

/// Ticket + hour band the on-device refine is keyed on. Arrivals are not part of the key;
/// the store keeps a delta from the median at inference and reapplies it.
struct ArrivalForecastFingerprint: Equatable, Hashable, Sendable {
    var title: String
    var tagNames: [String]
    var estimatedMinutes: Int
    var band: WorkHourBand

    init(_ context: ArrivalForecastContext) {
        title = context.title
        tagNames = context.tagNames
        estimatedMinutes = context.estimatedMinutes
        band = context.band
    }
}

enum ArrivalForecast {
    static let recentLimit = 8

    /// Prefer the current hour band when it has enough arrivals; otherwise all tagged rides.
    static func pooledRides(
        _ rides: [EstimateHeuristic.ArrivedRide],
        now: Date,
        calendar: Calendar
    ) -> (rides: [EstimateHeuristic.ArrivedRide], bandCount: Int) {
        let band = WorkHourBand.of(hour: calendar.component(.hour, from: now))
        let inBand = rides.filter {
            WorkHourBand.of(hour: calendar.component(.hour, from: $0.startedAt)) == band
        }
        if inBand.count >= EstimateHeuristic.minimumSampleCount {
            return (inBand, inBand.count)
        }
        return (rides, inBand.count)
    }

    static func context(
        ticket: Ticket,
        rides: [EstimateHeuristic.ArrivedRide],
        pooled: [EstimateHeuristic.ArrivedRide],
        medianMinutes: Int,
        now: Date,
        calendar: Calendar
    ) -> ArrivalForecastContext {
        let hour = calendar.component(.hour, from: now)
        let band = WorkHourBand.of(hour: hour)
        let recent = pooled
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(recentLimit)
            .map { ride in
                ArrivalForecastContext.RideRecord(
                    title: String(ride.title.prefix(40)),
                    startedLabel: ArrivalForecastPrompt.clockLabel(ride.startedAt, calendar: calendar),
                    estimatedMinutes: max(ride.estimatedSeconds / 60, 1),
                    actualMinutes: max(Int((ride.activeSeconds / 60).rounded()), 1),
                    budgetMinutes: max(ride.budgetSeconds / 60, 1),
                    extensionMinutes: max(ride.extensionAddedSeconds / 60, 0),
                    extensionReasons: ride.extensionReasons,
                    punctuality: ride.punctuality
                )
            }
        return ArrivalForecastContext(
            title: ticket.title,
            tagNames: ticket.tags.sorted { $0.sortOrder < $1.sortOrder }.map(\.name),
            estimatedMinutes: max(ticket.estimatedSeconds / 60, 1),
            nowLabel: ArrivalForecastPrompt.clockLabel(now, calendar: calendar),
            hour: hour,
            band: band,
            medianMinutes: medianMinutes,
            sampleCount: pooled.count,
            bandSampleCount: rides.filter {
                WorkHourBand.of(hour: calendar.component(.hour, from: $0.startedAt)) == band
            }.count,
            earlyCount: pooled.filter { $0.punctuality == .early }.count,
            onTimeCount: pooled.filter { $0.punctuality == .onTime }.count,
            lateCount: pooled.filter { $0.punctuality == .late }.count,
            extendedCount: pooled.filter { $0.extensionAddedSeconds > 0 }.count,
            recent: Array(recent)
        )
    }

    /// Keep the model from inventing a different task. Slack grows with the median.
    static func clampPredicted(_ predicted: Int, around median: Int) -> Int {
        let slack = max(12, Int((Double(median) * 0.4).rounded()))
        let lo = max(1, median - slack)
        let hi = min(TicketDurationScale.maxMinutes, median + slack)
        return min(max(predicted, lo), hi)
    }

    /// SwiftUI view tasks cancel when identity churns; Foundation Models surfaces that as this error.
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == "Swift.CancellationError"
    }

    /// Reapply a stored refine onto today's heuristic median. Nil stays on the median.
    static func appliedMinutes(
        resolved: Int?,
        medianAtRun: Int,
        currentMedian: Int
    ) -> Int? {
        guard let resolved else { return nil }
        if medianAtRun == currentMedian { return resolved }
        return clampPredicted(currentMedian + (resolved - medianAtRun), around: currentMedian)
    }

    /// Apply structured output onto the heuristic skeleton. Nil keeps the median.
    static func resolvedMinutes(from draft: ArrivalForecastDraft, medianMinutes: Int) -> Int? {
        guard draft.confidence != .low else { return nil }
        let clamped = clampPredicted(draft.predictedMinutes, around: medianMinutes)
        switch draft.weight {
        case .similar:
            return nil
        case .heavier:
            return clamped > medianMinutes ? clamped : nil
        case .lighter:
            return clamped < medianMinutes ? clamped : nil
        }
    }

    static func punctualityLabel(_ punctuality: ArrivalPunctuality) -> String {
        switch punctuality {
        case .onTime: "定時"
        case .early: "早着"
        case .late: "超過"
        case .notApplicable: "—"
        }
    }
}

enum ArrivalForecastPrompt {
    static let instructions = """
    あなたは発車前の所要分数を予測する。ユーザーへの助言・励まし・分割案・絵文字は禁止。
    先に題名・見積・開始時刻・延長・早着を履歴と比較し、thinking に短い推論を書く。
    中央値は骨格。題名や延長・早着の傾向がそれを正当化するときだけ分を動かす。
    題名にない事実は捏造しない。出力は指定の構造。分数は predictedMinutes に入れる。
    """

    static func userPrompt(for context: ArrivalForecastContext) -> String {
        let tags = context.tagNames.isEmpty ? "なし" : context.tagNames.joined(separator: "、")
        let rides = context.recent.map(rideLine).joined(separator: "\n")
        return """
        今回発車する切符:
        題名: \(context.title)
        経由: \(tags)
        見積もり: \(context.estimatedMinutes)分
        いま: \(context.nowLabel)（\(context.band.promptName)）

        骨格:
        中央値 \(context.medianMinutes)分（参考\(context.sampleCount)件、同じ時間帯 \(context.bandSampleCount)件）
        内訳: 早着\(context.earlyCount) · 定時\(context.onTimeCount) · 超過\(context.lateCount) · 延長\(context.extendedCount)件

        最近の到着:
        \(rides.isEmpty ? "なし" : rides)
        """
    }

    static func rideLine(_ ride: ArrivalForecastContext.RideRecord) -> String {
        var parts = [
            "\(ride.startedLabel) 開始 「\(ride.title)」",
            "見積\(ride.estimatedMinutes)分 → 実績\(ride.actualMinutes)分"
        ]
        if ride.extensionMinutes > 0 {
            var extensionPart = "延長+\(ride.extensionMinutes)分"
            if !ride.extensionReasons.isEmpty {
                extensionPart += "（\(ride.extensionReasons.joined(separator: "、"))）"
            }
            if ride.budgetMinutes != ride.estimatedMinutes {
                extensionPart += " 予算\(ride.budgetMinutes)分"
            }
            parts.append(extensionPart)
        }
        let punctuality = ArrivalForecast.punctualityLabel(ride.punctuality)
        let delta = ride.actualMinutes - ride.estimatedMinutes
        if ride.punctuality == .early, delta < 0 {
            parts.append("\(punctuality) \(abs(delta))分")
        } else if ride.punctuality == .late, delta > 0 {
            parts.append("\(punctuality) \(delta)分")
        } else {
            parts.append(punctuality)
        }
        return "- " + parts.joined(separator: " ")
    }

    static func clockLabel(_ date: Date, calendar: Calendar) -> String {
        let symbols = ["日", "月", "火", "水", "木", "金", "土"]
        let weekday = calendar.component(.weekday, from: date)
        let name = symbols[max(weekday - 1, 0) % 7]
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return "\(name) \(String(format: "%02d:%02d", hour, minute))"
    }
}
