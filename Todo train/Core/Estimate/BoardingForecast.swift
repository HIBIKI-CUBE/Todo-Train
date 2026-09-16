//
//  BoardingForecast.swift
//  Todo train
//
//  Wall-clock if boarded now, plus a prediction (not a recorded arrival).
//  Skeleton is tag + hour-band median. On-device model may refine minutes.
//

import Foundation

enum BoardingForecast {
    struct Snapshot: Equatable, Sendable {
        var scheduledArrival: Date
        var scheduledMinutes: Int
        var predictedArrival: Date?
        var predictedMinutes: Int?
        var sampleCount: Int

        var scheduledScaleMinutes: Int {
            TicketDurationScale.clampedMinutes(scheduledMinutes)
        }

        var predictedScaleMinutes: Int? {
            predictedMinutes.map(TicketDurationScale.clampedMinutes)
        }

        var hasPrediction: Bool { predictedArrival != nil && predictedMinutes != nil }

        func withPredictedMinutes(_ minutes: Int?, now: Date) -> Snapshot {
            guard let minutes else { return self }
            let clamped = max(minutes, 1)
            var copy = self
            copy.predictedMinutes = clamped
            copy.predictedArrival = now.addingTimeInterval(TimeInterval(clamped * 60))
            return copy
        }
    }

    static func tagFilter(for ticket: Ticket) -> Set<UUID>? {
        let ids = Set(ticket.tags.map(\.id))
        return ids.isEmpty ? nil : ids
    }

    static func make(
        now: Date,
        ticket: Ticket,
        sessions: [WorkSession],
        calendar: Calendar = .current
    ) -> Snapshot {
        make(
            now: now,
            estimatedSeconds: ticket.estimatedSeconds,
            rides: EstimateHeuristic.arrivedRides(
                from: sessions,
                matchingAnyTagIDs: tagFilter(for: ticket)
            ),
            calendar: calendar
        )
    }

    static func make(
        now: Date,
        estimatedSeconds: Int,
        sessions: [WorkSession],
        matchingAnyTagIDs tagIDs: Set<UUID>?,
        calendar: Calendar = .current
    ) -> Snapshot {
        make(
            now: now,
            estimatedSeconds: estimatedSeconds,
            rides: EstimateHeuristic.arrivedRides(from: sessions, matchingAnyTagIDs: tagIDs),
            calendar: calendar
        )
    }

    static func make(
        now: Date,
        estimatedSeconds: Int,
        rides: [EstimateHeuristic.ArrivedRide],
        calendar: Calendar = .current
    ) -> Snapshot {
        let estimate = max(estimatedSeconds, 0)
        let scheduledMinutes = max(estimate / 60, 1)
        let scheduledArrival = now.addingTimeInterval(TimeInterval(estimate))
        let pooled = ArrivalForecast.pooledRides(rides, now: now, calendar: calendar).rides
        let samples = pooled.map(\.activeSeconds)
        guard let predicted = predictedDuration(from: samples) else {
            return Snapshot(
                scheduledArrival: scheduledArrival,
                scheduledMinutes: scheduledMinutes,
                predictedArrival: nil,
                predictedMinutes: nil,
                sampleCount: samples.count
            )
        }
        return Snapshot(
            scheduledArrival: scheduledArrival,
            scheduledMinutes: scheduledMinutes,
            predictedArrival: now.addingTimeInterval(predicted.seconds),
            predictedMinutes: predicted.minutes,
            sampleCount: predicted.sampleCount
        )
    }

    /// Median minutes, not snapped to presets. Nil below the heuristic sample floor.
    static func predictedDuration(
        from samples: [TimeInterval]
    ) -> (seconds: TimeInterval, minutes: Int, sampleCount: Int)? {
        guard samples.count >= EstimateHeuristic.minimumSampleCount,
              let median = EstimateHeuristic.medianSeconds(samples) else {
            return nil
        }
        let minutes = max(Int((median / 60).rounded()), 1)
        return (median, minutes, samples.count)
    }

    static func timeString(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func predictedTimeString(from date: Date, timeZone: TimeZone = .current) -> String {
        "約 \(timeString(from: date, timeZone: timeZone))"
    }

    /// Wall-clock if you board now — the printed estimate, not remaining time.
    static let scheduledHeadline = "予定の到着"
    /// Forecast, not a recorded arrival.
    static let predictedHeadline = "予測の到着"

    static func durationLabel(minutes: Int) -> String {
        "\(minutes)分"
    }

    static func predictedDurationLabel(minutes: Int) -> String {
        "約\(minutes)分"
    }

    static func predictedCaption(minutes: Int, sampleCount: Int) -> String {
        "予測 約\(minutes)分 · 参考\(sampleCount)件"
    }

    static func forecastContext(
        ticket: Ticket,
        sessions: [WorkSession],
        now: Date,
        calendar: Calendar = .current
    ) -> ArrivalForecastContext? {
        let rides = EstimateHeuristic.arrivedRides(
            from: sessions,
            matchingAnyTagIDs: tagFilter(for: ticket)
        )
        let pooled = ArrivalForecast.pooledRides(rides, now: now, calendar: calendar)
        guard let predicted = predictedDuration(from: pooled.rides.map(\.activeSeconds)) else {
            return nil
        }
        return ArrivalForecast.context(
            ticket: ticket,
            rides: rides,
            pooled: pooled.rides,
            medianMinutes: predicted.minutes,
            now: now,
            calendar: calendar
        )
    }
}
