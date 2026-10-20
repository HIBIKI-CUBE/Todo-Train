//
//  ServiceCabinOverview.swift
//  Todo train
//
//  Shutdown trace: the civil day compresses into the panel, then the
//  service window takes the scale. Gaps inside that window stay linear.
//

import CoreGraphics
import Foundation

struct ServiceCabinOverviewBounds: Equatable, Sendable {
    var start: Date
    var end: Date
}

struct ServiceCabinOverviewWindow: Equatable, Sendable {
    var start: Date
    var end: Date
    var pointsPerMinute: Double
    var height: Double

    func layout(calendar: Calendar) -> DayClockLayout {
        DayClockLayout(
            start: start,
            end: end,
            pointsPerMinute: pointsPerMinute,
            laneByRideID: [:],
            laneCount: 1,
            hourTicks: SessionTimeline.hourTicks(from: start, to: end, calendar: calendar)
        )
    }
}

enum ServiceCabinOverview {
    /// Short services still show this much clock. The scale never goes past history.
    static let minimumSpan: TimeInterval = 2 * 60 * 60

    /// Room before the first mark and after the last, so the service is not flush with the edge.
    private static let edgeContext: TimeInterval = 60 * 60

    /// Hour labels need about this many points, or they stack when the day is compressed.
    private static let hourLabelPitch: Double = 28

    static func serviceBounds(
        startedAt: Date?,
        now: Date,
        dayStart: Date,
        dayEnd: Date,
        rides: [(start: Date, end: Date)]
    ) -> ServiceCabinOverviewBounds {
        var marks = [now]
        if let startedAt {
            marks.append(startedAt)
        }
        for ride in rides {
            marks.append(ride.start)
            marks.append(ride.end)
        }
        let earliest = marks.min() ?? now
        let latest = max(marks.max() ?? now, earliest)
        var start = earliest.addingTimeInterval(-edgeContext)
        var end = latest.addingTimeInterval(edgeContext)
        if end.timeIntervalSince(start) < minimumSpan {
            let extra = minimumSpan - end.timeIntervalSince(start)
            start -= extra / 2
            end += extra / 2
        }
        if start < dayStart {
            start = dayStart
        }
        if end > dayEnd {
            end = dayEnd
        }
        if end <= start {
            end = min(dayEnd, start.addingTimeInterval(minimumSpan))
        }
        return ServiceCabinOverviewBounds(start: start, end: end)
    }

    static func fitted(
        bounds: ServiceCabinOverviewBounds,
        viewportHeight: CGFloat,
        calendar: Calendar,
        slack: CGFloat
    ) -> ServiceCabinOverviewWindow {
        let aligned = SessionTimeline.hourAlignedRange(
            start: bounds.start,
            end: bounds.end,
            calendar: calendar
        )
        let start = aligned.start
        let end = aligned.end > aligned.start ? aligned.end : bounds.end
        return scale(start: start, end: end, viewportHeight: viewportHeight, slack: slack)
    }

    static func fullDay(
        on day: Date,
        viewportHeight: CGFloat,
        calendar: Calendar,
        slack: CGFloat
    ) -> ServiceCabinOverviewWindow {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(86_400)
        return scale(start: start, end: end, viewportHeight: viewportHeight, slack: slack)
    }

    static func hourStride(pointsPerMinute: Double) -> Int {
        let pointsPerHour = pointsPerMinute * 60
        guard pointsPerHour > 0 else { return 1 }
        return max(1, Int((hourLabelPitch / pointsPerHour).rounded(.up)))
    }

    private static func scale(
        start: Date,
        end: Date,
        viewportHeight: CGFloat,
        slack: CGFloat
    ) -> ServiceCabinOverviewWindow {
        let minutes = max(end.timeIntervalSince(start) / 60, 0.001)
        let usable = max(Double(viewportHeight) - Double(slack), 1)
        let natural = minutes * SessionTimeline.pointsPerMinute
        if natural <= usable {
            return ServiceCabinOverviewWindow(
                start: start,
                end: end,
                pointsPerMinute: SessionTimeline.pointsPerMinute,
                height: natural
            )
        }
        return ServiceCabinOverviewWindow(
            start: start,
            end: end,
            pointsPerMinute: usable / minutes,
            height: usable
        )
    }
}
