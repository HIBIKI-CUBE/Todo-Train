import Foundation

/// Weekday gate shared with reminders. Saturday, Sunday, and Japanese public holidays stay quiet.
public enum ReminderDay {
    public static func allows(_ date: Date, calendar: Calendar = .current) -> Bool {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let weekday = gregorian.component(.weekday, from: date)
        if weekday == 1 || weekday == 7 { return false }
        return !JapaneseHolidays.isHoliday(date, calendar: gregorian)
    }
}

/// National holidays under the current law (山の日, スポーツの日, 振替休日, 国民の休日).
enum JapaneseHolidays {
    static func isHoliday(_ date: Date, calendar: Calendar) -> Bool {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return days(in: year, calendar: calendar).contains(Day(month: month, day: day))
    }

    private struct Day: Hashable {
        var month: Int
        var day: Int
    }

    private static func days(in year: Int, calendar: Calendar) -> Set<Day> {
        var holidays = Set<Day>()
        func add(month: Int, day: Int) {
            holidays.insert(Day(month: month, day: day))
        }
        for (month, day) in [(1, 1), (2, 11), (2, 23), (4, 29), (5, 3), (5, 4), (5, 5), (8, 11), (11, 3), (11, 23)] {
            add(month: month, day: day)
        }
        if let day = nthWeekday(year: year, month: 1, weekday: 2, nth: 2, calendar: calendar) {
            add(month: 1, day: day)
        }
        if let day = nthWeekday(year: year, month: 7, weekday: 2, nth: 3, calendar: calendar) {
            add(month: 7, day: day)
        }
        if let day = nthWeekday(year: year, month: 9, weekday: 2, nth: 3, calendar: calendar) {
            add(month: 9, day: day)
        }
        if let day = nthWeekday(year: year, month: 10, weekday: 2, nth: 2, calendar: calendar) {
            add(month: 10, day: day)
        }
        add(month: 3, day: equinox(spring: true, year: year))
        add(month: 9, day: equinox(spring: false, year: year))

        var substitutes = Set<Day>()
        for holiday in holidays {
            guard let date = date(year: year, month: holiday.month, day: holiday.day, calendar: calendar) else {
                continue
            }
            guard calendar.component(.weekday, from: date) == 1 else { continue }
            var cursor = calendar.date(byAdding: .day, value: 1, to: date)
            while let next = cursor {
                let day = Day(
                    month: calendar.component(.month, from: next),
                    day: calendar.component(.day, from: next)
                )
                if !holidays.contains(day) && !substitutes.contains(day) {
                    substitutes.insert(day)
                    break
                }
                cursor = calendar.date(byAdding: .day, value: 1, to: next)
            }
        }
        holidays.formUnion(substitutes)

        var citizens = Set<Day>()
        var cursor = date(year: year, month: 1, day: 1, calendar: calendar)
        let end = date(year: year + 1, month: 1, day: 1, calendar: calendar)
        while let day = cursor, let end, day < end {
            let next = calendar.date(byAdding: .day, value: 1, to: day)
            let previous = calendar.date(byAdding: .day, value: -1, to: day)
            if calendar.component(.weekday, from: day) != 1,
               let previous, let next,
               contains(previous, holidays, calendar: calendar),
               contains(next, holidays, calendar: calendar),
               !contains(day, holidays, calendar: calendar)
            {
                citizens.insert(
                    Day(
                        month: calendar.component(.month, from: day),
                        day: calendar.component(.day, from: day)
                    )
                )
            }
            cursor = next
        }
        holidays.formUnion(citizens)
        return holidays
    }

    private static func contains(_ date: Date, _ days: Set<Day>, calendar: Calendar) -> Bool {
        days.contains(
            Day(
                month: calendar.component(.month, from: date),
                day: calendar.component(.day, from: date)
            )
        )
    }

    private static func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        var parts = DateComponents()
        parts.year = year
        parts.month = month
        parts.day = day
        parts.hour = 12
        return calendar.date(from: parts)
    }

    /// `weekday` is Gregorian (Monday = 2). `nth` starts at 1.
    private static func nthWeekday(
        year: Int,
        month: Int,
        weekday: Int,
        nth: Int,
        calendar: Calendar
    ) -> Int? {
        guard let first = date(year: year, month: month, day: 1, calendar: calendar) else { return nil }
        let firstWeekday = calendar.component(.weekday, from: first)
        var delta = weekday - firstWeekday
        if delta < 0 { delta += 7 }
        let day = 1 + delta + (nth - 1) * 7
        guard let date = date(year: year, month: month, day: day, calendar: calendar) else { return nil }
        guard calendar.component(.month, from: date) == month else { return nil }
        return day
    }

    /// Shinkawa formula, valid around 1980–2099.
    private static func equinox(spring: Bool, year: Int) -> Int {
        let years = Double(year - 1980)
        let base = spring ? 20.8431 : 23.2488
        return Int((base + 0.242194 * years - (years / 4).rounded(.down)).rounded(.down))
    }
}

/// Right drag or two-finger swipe on the gap card. Release past half the card width.
public enum ArrivalGapBoardGesture {
    public static func commits(translationX: Double, translationY: Double, cardWidth: Double) -> Bool {
        guard cardWidth > 0 else { return false }
        return translationX > cardWidth / 2 && translationX > abs(translationY)
    }
}

/// What iPhone should show and store for the blank after an arrival stamp.
public struct ArrivalGapDecision: Equatable, Sendable {
    public var visible: NudgeGapItem?
    public var upcoming: [NudgeGapItem]
    public var newlyDue: [NudgeGapItem]
    public var wakeAt: Date?
    public var prompt: String?

    public static let hidden = ArrivalGapDecision(
        visible: nil,
        upcoming: [],
        newlyDue: [],
        wakeAt: nil,
        prompt: nil
    )
}

public enum ArrivalGapDeciding {
    public static let dismissMarker = "gapClosed"
    /// Same fresh window as a ride chime. A later wake does not replay the sound.
    public static let fresh: TimeInterval = 2

    public static func decide(
        stampedAt: Date?,
        now: Date,
        arrivalScreenOpen: Bool,
        blocked: Bool,
        dismissed: Bool,
        cabinEnabled: Bool,
        fired: Set<NudgeGap>,
        foreground: [NudgeSurface],
        macAttending: Bool,
        reservedTitle: String?,
        calendar: Calendar = .current
    ) -> ArrivalGapDecision {
        guard cabinEnabled, !blocked, !dismissed, let stampedAt else { return .hidden }
        guard ReminderDay.allows(stampedAt, calendar: calendar) else { return .hidden }
        guard ReminderDay.allows(now, calendar: calendar) else { return .hidden }

        let slots = NudgePlanner.gaps(
            NudgeGapInput(
                stampedAt: stampedAt,
                arrivalScreenOpen: false,
                foreground: foreground,
                macAttending: macAttending,
                now: stampedAt
            )
        )
        guard let gap1 = slots.first(where: { $0.stage == .gap1 }),
              let gap2 = slots.first(where: { $0.stage == .gap2 })
        else { return .hidden }

        if arrivalScreenOpen {
            let wake = [gap1.fireAt, gap2.fireAt].first { $0 > now }
            return ArrivalGapDecision(visible: nil, upcoming: [], newlyDue: [], wakeAt: wake, prompt: nil)
        }
        if now < gap1.fireAt {
            return ArrivalGapDecision(visible: nil, upcoming: [], newlyDue: [], wakeAt: gap1.fireAt, prompt: nil)
        }

        let due = slots.filter { $0.fireAt <= now && !fired.contains($0.stage) }
        if now > gap2.fireAt {
            return ArrivalGapDecision(visible: nil, upcoming: [], newlyDue: due, wakeAt: nil, prompt: nil)
        }

        let prompt = reservedTitle.map { CabinCopy.readyToBoard(title: $0) } ?? CabinCopy.idle
        let wakeAt = now < gap2.fireAt ? gap2.fireAt : gap2.fireAt.addingTimeInterval(1)
        return ArrivalGapDecision(
            visible: slots.last { $0.fireAt <= now },
            upcoming: slots.filter { $0.fireAt > now },
            newlyDue: due,
            wakeAt: wakeAt,
            prompt: prompt
        )
    }
}

/// Mac PiP while the snap carries an arrival gap. One reserved face, or the idle line.
public struct ArrivalGapChrome: Equatable, Sendable {
    public var prompt: String
    public var title: String
    public var canBoard: Bool
    public var holdLamp: Bool

    public init(prompt: String, title: String, canBoard: Bool, holdLamp: Bool) {
        self.prompt = prompt
        self.title = title
        self.canBoard = canBoard
        self.holdLamp = holdLamp
    }

    public static func make(snap: SnapPlaintext, cabinEnabled: Bool) -> ArrivalGapChrome? {
        guard cabinEnabled, snap.phase == .idle, snap.nudge?.kind == .gap else { return nil }
        guard snap.nudge?.stage == .gap1 || snap.nudge?.stage == .gap2 else { return nil }
        let title = snap.reserved?.title ?? ""
        let prompt = snap.reserved.map { CabinCopy.readyToBoard(title: $0.title) } ?? CabinCopy.idle
        return ArrivalGapChrome(
            prompt: prompt,
            title: title,
            canBoard: snap.reserved != nil,
            holdLamp: snap.nudge?.ringSurface == .mac
        )
    }
}
