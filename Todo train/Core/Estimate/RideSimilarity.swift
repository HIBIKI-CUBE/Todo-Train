//
//  RideSimilarity.swift
//  Todo train
//
//  過去の到着を一つに選んで採点する。発券の見積と発車前の予測は、ここから乗車を受け取る。
//  題名の文字 2-gram、タグ、乗り継ぎを手がかりにし、時間帯と平日／休日は小さい掛け目。
//  乗り継ぎで別の切符とつながる乗車は、点数に底を足して常に上に置く。
//

import Foundation
import TodoTrainSync

enum RideSimilarity {
    /// 題名の重み。タグと足して 1。
    static let titleWeight = 0.65
    /// タグの Jaccard。両方空なら 0（タグが無いこと自体は一致にしない）。
    static let tagWeight = 0.35
    /// 同じ時間帯の掛け目。
    static let hourBandFactor = 1.08
    /// 平日同士、または休日同士（土日と日本の祝日）の掛け目。
    static let dayKindFactor = 1.04
    /// 別切符との乗り継ぎ。内容の満点に掛け目を掛けた値より大きい。
    static let lineageBase = 2.0
    /// 書き出しに残す、先行する乗車の上限。
    static let candidateLimit = 20
    /// 直前の切符との発券間隔がこれを超えたら新しい組。組の id は一番早い切符。
    static let batchGap: TimeInterval = 15 * 60

    struct Query: Equatable, Sendable {
        var title: String
        var tagIDs: Set<UUID>
        var ticketID: UUID?
        var lineageGroupID: UUID?
        var at: Date
    }

    struct Ride: Equatable, Sendable {
        var id: UUID
        var ticketID: UUID?
        var title: String
        var tagIDs: Set<UUID>
        var lineageGroupID: UUID?
        var startedAt: Date
        var activeSeconds: TimeInterval
    }

    struct CueScores: Equatable, Sendable {
        var titleNGram: Double
        var tag: Double
        var lineage: Double
        var hourBand: Double
        var dayKind: Double
    }

    struct ScoredRide: Equatable, Sendable {
        var ride: Ride
        var cues: CueScores
        var score: Double

        var hasContentMatch: Bool {
            cues.lineage > 0 || cues.titleNGram > 0 || cues.tag > 0
        }
    }

    struct Selection: Equatable {
        var eligible: [EstimateHeuristic.ArrivedRide]
        var chosen: [ScoredRide]
    }

    struct IssuedTicket: Equatable, Sendable {
        var id: UUID
        var createdAt: Date
    }

    struct Occupancy: Equatable, Sendable {
        var id: UUID
        var startsAt: Date
        var endsAt: Date
        var isCancelled: Bool
    }

    struct DayRide: Equatable, Sendable {
        var id: UUID
        var serviceDayID: UUID?
        var startedAt: Date
        var endedAt: Date?
        var activeSeconds: TimeInterval
    }

    struct DaySlot: Equatable, Sendable {
        var ordinal: Int
        var cumulativeActiveSecondsBefore: TimeInterval
        var previousRideID: UUID?
        var nextRideID: UUID?
        var secondsSincePreviousArrival: TimeInterval?
    }

    /// 系譜か、題名かタグの重なりがある乗車が 3 件以上ならそれだけ。足りなければ条件を満たす到着を全部。
    static func ridesForEstimate(_ ranked: [ScoredRide]) -> [ScoredRide] {
        let similar = ranked.filter(\.hasContentMatch)
        if similar.count >= EstimateHeuristic.minimumSampleCount {
            return similar
        }
        return ranked
    }

    /// 点数の高い順。同点は発車が新しい順、その次に乗車 id。
    static func rank(
        query: Query,
        rides: [Ride],
        calendar: Calendar = .current
    ) -> [ScoredRide] {
        var context = ScoringContext(calendar: calendar)
        var preparedQuery = context.prepareQuery(query)
        var prepared: [PreparedRide] = []
        prepared.reserveCapacity(rides.count)
        var needsQueryUnigrams = false
        for ride in rides {
            let preparedRide = context.prepareRide(ride, queryLength: preparedQuery.length)
            if preparedQuery.length >= 2, preparedRide.length == 1 {
                needsQueryUnigrams = true
            }
            prepared.append(preparedRide)
        }
        if needsQueryUnigrams {
            preparedQuery.unigrams = context.unigrams(for: preparedQuery.title)
        }
        var scored: [ScoredRide] = []
        scored.reserveCapacity(prepared.count)
        for ride in prepared {
            scored.append(score(preparedQuery, ride: ride))
        }
        scored.sort(by: orderedBefore)
        return scored
    }

    /// 各 subject について、pool のうちそれより前の乗車を点数順に `candidateLimit` 件。
    static func priorCandidates(
        for subjects: [Ride],
        among pool: [Ride],
        calendar: Calendar = .current
    ) -> [UUID: [ScoredRide]] {
        var context = ScoringContext(calendar: calendar)
        var preparedPool: [PreparedRide] = []
        preparedPool.reserveCapacity(pool.count)
        for ride in pool {
            preparedPool.append(context.preparePoolRide(ride))
        }
        let poolHasSingleCharacter = preparedPool.contains { $0.length == 1 }
        var result: [UUID: [ScoredRide]] = [:]
        result.reserveCapacity(subjects.count)
        for subject in subjects {
            var query = context.prepareQuery(
                Query(
                    title: subject.title,
                    tagIDs: subject.tagIDs,
                    ticketID: subject.ticketID,
                    lineageGroupID: subject.lineageGroupID,
                    at: subject.startedAt
                )
            )
            if poolHasSingleCharacter, query.length >= 2 {
                query.unigrams = context.unigrams(for: subject.title)
            }
            let scored = preparedPool
                .filter { isPrior($0.ride, to: subject) }
                .map { score(query, ride: $0) }
                .sorted(by: orderedBefore)
            result[subject.id] = Array(scored.prefix(candidateLimit))
        }
        return result
    }

    /// 到着、走行 60 秒以上、`ForecastExclusion` で外れない乗車だけを採点し、見積に使う部分集合を返す。
    @MainActor
    static func select(
        title: String,
        tagIDs: Set<UUID>,
        ticket: Ticket?,
        sessions: [WorkSession],
        now: Date,
        calendar: Calendar = .current
    ) -> Selection {
        let eligible = ForecastSample.eligible(
            EstimateHeuristic.arrivedRides(from: sessions, matchingAnyTagIDs: nil)
        )
        let members: Set<UUID>
        let group: UUID?
        if let ticket {
            members = component(of: ticket)
            group = members.min { $0.uuidString < $1.uuidString }
        } else {
            members = []
            group = nil
        }
        let query = Query(
            title: title,
            tagIDs: tagIDs,
            ticketID: ticket?.id,
            lineageGroupID: group,
            at: now
        )
        let features = eligible.map { ride -> Ride in
            let rideGroup: UUID?
            if let ticketID = ride.ticketID, members.contains(ticketID), let group {
                rideGroup = group
            } else {
                rideGroup = ride.ticketID
            }
            return Ride(
                id: ride.id,
                ticketID: ride.ticketID,
                title: ride.title,
                tagIDs: ride.tagIDs,
                lineageGroupID: rideGroup,
                startedAt: ride.startedAt,
                activeSeconds: ride.activeSeconds
            )
        }
        let ranked = rank(query: query, rides: features, calendar: calendar)
        return Selection(eligible: eligible, chosen: ridesForEstimate(ranked))
    }

    /// つながる切符の組。識別子は組の中で UUID 文字列が最小の切符。孤立した切符は自分の id。
    static func lineageGroups(ticketIDs: [UUID], links: [(UUID, UUID)]) -> [UUID: UUID] {
        var parent: [UUID: UUID] = [:]
        for id in ticketIDs {
            parent[id] = id
        }
        for (lhs, rhs) in links {
            if parent[lhs] == nil { parent[lhs] = lhs }
            if parent[rhs] == nil { parent[rhs] = rhs }
        }

        func find(_ id: UUID) -> UUID {
            var root = id
            while let next = parent[root], next != root {
                root = next
            }
            var cursor = id
            while cursor != root {
                let next = parent[cursor] ?? root
                parent[cursor] = root
                cursor = next
            }
            return root
        }

        for (lhs, rhs) in links {
            let left = find(lhs)
            let right = find(rhs)
            if left == right { continue }
            if left.uuidString < right.uuidString {
                parent[right] = left
            } else {
                parent[left] = right
            }
        }

        var groups: [UUID: UUID] = [:]
        for id in parent.keys {
            groups[id] = find(id)
        }
        return groups
    }

    /// 直前の切符から `batchGap` を超えたら新しい組。組の id は、その組で一番早い切符の id。
    static func batchIDs(
        _ tickets: [IssuedTicket],
        gap: TimeInterval = batchGap
    ) -> [UUID: UUID] {
        let ordered = tickets.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var batches: [UUID: UUID] = [:]
        var batchID: UUID?
        var previous: Date?
        for ticket in ordered {
            if let previous, ticket.createdAt.timeIntervalSince(previous) > gap {
                batchID = ticket.id
            } else if batchID == nil {
                batchID = ticket.id
            }
            if let batchID {
                batches[ticket.id] = batchID
            }
            previous = ticket.createdAt
        }
        return batches
    }

    /// 発車以降に始まる、取り消されておらず長さのあるブロックまでの秒。確認待ちも含む。題名は見ない。
    /// 同じ運行日（`serviceDay` が無いときは暦日）のブロックだけを見る。
    static func slack(
        departedAt: Date,
        blocks: [Occupancy],
        calendar: Calendar = .current,
        serviceDay: Range<Date>? = nil
    ) -> TimeInterval? {
        let dayStart: Date
        let dayEnd: Date
        if let serviceDay {
            dayStart = serviceDay.lowerBound
            dayEnd = serviceDay.upperBound
        } else {
            dayStart = calendar.startOfDay(for: departedAt)
            dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        }
        let upcoming = blocks.filter { block in
            !block.isCancelled
                && block.endsAt > block.startsAt
                && block.startsAt >= departedAt
                && block.startsAt >= dayStart
                && block.startsAt < dayEnd
        }
        guard let next = upcoming.min(by: { lhs, rhs in
            if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }) else {
            return nil
        }
        return next.startsAt.timeIntervalSince(departedAt)
    }

    /// 同じ運行の中の順番。運行に入らない乗車は結果に入れない。
    static func daySlots(_ rides: [DayRide]) -> [UUID: DaySlot] {
        var groups: [UUID: [DayRide]] = [:]
        for ride in rides {
            guard let dayID = ride.serviceDayID else { continue }
            groups[dayID, default: []].append(ride)
        }
        var slots: [UUID: DaySlot] = [:]
        for members in groups.values {
            let ordered = members.sorted { lhs, rhs in
                if lhs.startedAt != rhs.startedAt { return lhs.startedAt < rhs.startedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            var cumulative: TimeInterval = 0
            for index in ordered.indices {
                let ride = ordered[index]
                let previous = index > 0 ? ordered[index - 1] : nil
                let next = index + 1 < ordered.count ? ordered[index + 1] : nil
                let sincePrevious: TimeInterval?
                if let endedAt = previous?.endedAt {
                    sincePrevious = ride.startedAt.timeIntervalSince(endedAt)
                } else {
                    sincePrevious = nil
                }
                slots[ride.id] = DaySlot(
                    ordinal: index + 1,
                    cumulativeActiveSecondsBefore: cumulative,
                    previousRideID: previous?.id,
                    nextRideID: next?.id,
                    secondsSincePreviousArrival: sincePrevious
                )
                cumulative += ride.activeSeconds
            }
        }
        return slots
    }

    @MainActor
    static func component(of ticket: Ticket) -> Set<UUID> {
        var seen: Set<UUID> = []
        var stack: [Ticket] = [ticket]
        while let current = stack.popLast() {
            guard seen.insert(current.id).inserted else { continue }
            for lineage in current.parentLineages {
                if let parent = lineage.parent {
                    stack.append(parent)
                }
            }
            for lineage in current.childLineages {
                if let child = lineage.child {
                    stack.append(child)
                }
            }
        }
        return seen
    }

    // MARK: - Scoring

    /// ソート済みの文字 n-gram。同じハッシュは回数を足す（以前の辞書と同じ衝突の扱い）。
    private struct GramList {
        var keys: [UInt64]
        var counts: [UInt16]
        var total: Int

        static let empty = GramList(keys: [], counts: [], total: 0)

        private init(keys: [UInt64], counts: [UInt16], total: Int) {
            self.keys = keys
            self.counts = counts
            self.total = total
        }

        init(scalars: [UInt32], n: Int) {
            let count = scalars.count
            guard n > 0, count >= n else {
                self = .empty
                return
            }
            let total = count - n + 1
            var hashes = [UInt64](repeating: 0, count: total)
            for index in 0..<total {
                var hash: UInt64 = 14_695_981_039_346_656_037
                for offset in 0..<n {
                    hash ^= UInt64(scalars[index + offset])
                    hash &*= 1_099_511_628_211
                }
                hashes[index] = hash
            }
            hashes.sort()
            var keys: [UInt64] = []
            var counts: [UInt16] = []
            keys.reserveCapacity(total)
            var cursor = 0
            while cursor < total {
                let hash = hashes[cursor]
                var run: UInt16 = 1
                cursor += 1
                while cursor < total, hashes[cursor] == hash {
                    run += 1
                    cursor += 1
                }
                keys.append(hash)
                counts.append(run)
            }
            self.keys = keys
            self.counts = counts
            self.total = total
        }

        func dice(with other: GramList) -> Double {
            guard total > 0, other.total > 0 else { return 0 }
            var overlap = 0
            var left = 0
            var right = 0
            while left < keys.count, right < other.keys.count {
                let lhs = keys[left]
                let rhs = other.keys[right]
                if lhs == rhs {
                    overlap += Int(min(counts[left], other.counts[right]))
                    left += 1
                    right += 1
                } else if lhs < rhs {
                    left += 1
                } else {
                    right += 1
                }
            }
            return (2 * Double(overlap)) / Double(total + other.total)
        }
    }

    private struct PreparedQuery {
        var title: String
        var tagIDs: Set<UUID>
        var ticketID: UUID?
        var lineageGroupID: UUID?
        var unigrams: GramList
        var bigrams: GramList
        var length: Int
        var band: WorkHourBand
        var offDay: Bool
    }

    private struct PreparedRide {
        var ride: Ride
        var unigrams: GramList
        var bigrams: GramList
        var length: Int
        var band: WorkHourBand
        var offDay: Bool
    }

    /// 1 回の採点の中で、題名の n-gram と平日／休日を使い回す。
    private struct ScoringContext {
        var calendar: Calendar
        var usesGregorianClock: Bool
        var offDays: [Int64: Bool]
        var titles: [String: CachedTitle]

        init(calendar: Calendar) {
            self.calendar = calendar
            usesGregorianClock = calendar.identifier == .gregorian
            offDays = [:]
            titles = [:]
        }

        mutating func prepareQuery(_ query: Query) -> PreparedQuery {
            let placement = placement(of: query.at)
            let text = features(for: query.title, queryLength: 0, asQuery: true)
            return PreparedQuery(
                title: query.title,
                tagIDs: query.tagIDs,
                ticketID: query.ticketID,
                lineageGroupID: query.lineageGroupID,
                unigrams: text.unigrams,
                bigrams: text.bigrams,
                length: text.length,
                band: placement.band,
                offDay: placement.offDay
            )
        }

        /// 問い合わせの長さに必要な n-gram だけ作る。1 文字の乗車は unigram。
        mutating func prepareRide(_ ride: Ride, queryLength: Int) -> PreparedRide {
            let placement = placement(of: ride.startedAt)
            let text = features(for: ride.title, queryLength: queryLength, asQuery: false)
            return PreparedRide(
                ride: ride,
                unigrams: text.unigrams,
                bigrams: text.bigrams,
                length: text.length,
                band: placement.band,
                offDay: placement.offDay
            )
        }

        /// 先行候補は問い合わせの長さが混ざるので、空でない題名は両方作る。
        mutating func preparePoolRide(_ ride: Ride) -> PreparedRide {
            let placement = placement(of: ride.startedAt)
            var cached = cachedTitle(ride.title)
            if cached.length > 0, !cached.didUnigrams || !cached.didBigrams {
                cached.ensureUnigrams()
                cached.ensureBigrams()
                titles[ride.title] = cached
            }
            return PreparedRide(
                ride: ride,
                unigrams: cached.unigrams,
                bigrams: cached.bigrams,
                length: cached.length,
                band: placement.band,
                offDay: placement.offDay
            )
        }

        mutating func unigrams(for title: String) -> GramList {
            var cached = cachedTitle(title)
            cached.ensureUnigrams()
            titles[title] = cached
            return cached.unigrams
        }

        private mutating func features(
            for title: String,
            queryLength: Int,
            asQuery: Bool
        ) -> (length: Int, unigrams: GramList, bigrams: GramList) {
            if !asQuery, queryLength == 0 {
                return (0, .empty, .empty)
            }
            var cached = cachedTitle(title)
            let length = cached.length
            let wantBigrams: Bool
            let wantUnigrams: Bool
            if asQuery {
                wantBigrams = length >= 2
                wantUnigrams = length == 1
            } else if queryLength == 1 {
                wantBigrams = false
                wantUnigrams = length > 0
            } else if queryLength >= 2 {
                wantBigrams = length >= 2
                wantUnigrams = length == 1
            } else {
                wantBigrams = false
                wantUnigrams = false
            }
            let dirty = (wantBigrams && !cached.didBigrams) || (wantUnigrams && !cached.didUnigrams)
            if wantBigrams { cached.ensureBigrams() }
            if wantUnigrams { cached.ensureUnigrams() }
            if dirty {
                titles[title] = cached
            }
            return (length, cached.unigrams, cached.bigrams)
        }

        private mutating func cachedTitle(_ title: String) -> CachedTitle {
            if let existing = titles[title] {
                return existing
            }
            let created = CachedTitle(title)
            titles[title] = created
            return created
        }

        private mutating func placement(of date: Date) -> (band: WorkHourBand, offDay: Bool) {
            let day: Int64
            let hour: Int
            if usesGregorianClock {
                let parts = Self.gregorianDayAndHour(date, timeZone: calendar.timeZone)
                day = parts.day
                hour = parts.hour
            } else {
                let parts = calendar.dateComponents([.year, .month, .day, .hour], from: date)
                day = Int64((parts.year ?? 0) * 10_000 + (parts.month ?? 0) * 100 + (parts.day ?? 0))
                hour = parts.hour ?? 0
            }
            let band = WorkHourBand.of(hour: hour)
            if let offDay = offDays[day] {
                return (band, offDay)
            }
            let offDay = !ReminderDay.allows(date, calendar: calendar)
            offDays[day] = offDay
            return (band, offDay)
        }

        private static func gregorianDayAndHour(_ date: Date, timeZone: TimeZone) -> (day: Int64, hour: Int) {
            let offset = Int64(timeZone.secondsFromGMT(for: date))
            let local = Int64(date.timeIntervalSince1970.rounded(.down)) + offset
            let daySeconds: Int64 = 86_400
            var day = local / daySeconds
            var seconds = local % daySeconds
            if seconds < 0 {
                seconds += daySeconds
                day -= 1
            }
            return (day, Int(seconds / 3600))
        }
    }

    private struct CachedTitle {
        var scalars: [UInt32]
        var unigrams: GramList
        var bigrams: GramList
        var didUnigrams: Bool
        var didBigrams: Bool

        init(_ title: String) {
            let normalized = RideSimilarity.normalize(title)
            var values: [UInt32] = []
            values.reserveCapacity(normalized.unicodeScalars.underestimatedCount)
            for scalar in normalized.unicodeScalars {
                values.append(scalar.value)
            }
            scalars = values
            unigrams = .empty
            bigrams = .empty
            didUnigrams = false
            didBigrams = false
        }

        var length: Int { scalars.count }

        mutating func ensureUnigrams() {
            guard !didUnigrams else { return }
            unigrams = GramList(scalars: scalars, n: 1)
            didUnigrams = true
        }

        mutating func ensureBigrams() {
            guard !didBigrams else { return }
            bigrams = length >= 2 ? GramList(scalars: scalars, n: 2) : .empty
            didBigrams = true
        }
    }

    private static func score(_ query: PreparedQuery, ride: PreparedRide) -> ScoredRide {
        let title = titleScore(query, ride)
        let tag = tagScore(query.tagIDs, ride.ride.tagIDs)
        let lineage = lineageScore(query, ride.ride)
        let hourBand: Double = query.band == ride.band ? 1 : 0
        let dayKind: Double = query.offDay == ride.offDay ? 1 : 0
        let content = titleWeight * title + tagWeight * tag
        let multiplier = (hourBand > 0 ? hourBandFactor : 1) * (dayKind > 0 ? dayKindFactor : 1)
        let score = (lineage > 0 ? lineageBase : 0) + content * multiplier
        return ScoredRide(
            ride: ride.ride,
            cues: CueScores(
                titleNGram: title,
                tag: tag,
                lineage: lineage,
                hourBand: hourBand,
                dayKind: dayKind
            ),
            score: score
        )
    }

    private static func titleScore(_ query: PreparedQuery, _ ride: PreparedRide) -> Double {
        guard query.length > 0, ride.length > 0 else { return 0 }
        if query.length >= 2, ride.length >= 2 {
            return query.bigrams.dice(with: ride.bigrams)
        }
        return query.unigrams.dice(with: ride.unigrams)
    }

    private static func tagScore(_ lhs: Set<UUID>, _ rhs: Set<UUID>) -> Double {
        let leftCount = lhs.count
        let rightCount = rhs.count
        guard leftCount > 0, rightCount > 0 else { return 0 }
        var shared = 0
        if leftCount <= rightCount {
            for id in lhs where rhs.contains(id) {
                shared += 1
            }
        } else {
            for id in rhs where lhs.contains(id) {
                shared += 1
            }
        }
        guard shared > 0 else { return 0 }
        return Double(shared) / Double(leftCount + rightCount - shared)
    }

    /// 同じ切符の前の乗車は乗り継ぎに数えない。別の切符と同じ組のときだけ 1。
    private static func lineageScore(_ query: PreparedQuery, _ ride: Ride) -> Double {
        guard let group = query.lineageGroupID, group == ride.lineageGroupID else { return 0 }
        guard let queryTicket = query.ticketID, let rideTicket = ride.ticketID, queryTicket != rideTicket else {
            return 0
        }
        return 1
    }

    private static func orderedBefore(_ lhs: ScoredRide, _ rhs: ScoredRide) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.ride.startedAt != rhs.ride.startedAt { return lhs.ride.startedAt > rhs.ride.startedAt }
        return lhs.ride.id.uuidString < rhs.ride.id.uuidString
    }

    private static func isPrior(_ candidate: Ride, to subject: Ride) -> Bool {
        if candidate.id == subject.id { return false }
        if candidate.startedAt != subject.startedAt {
            return candidate.startedAt < subject.startedAt
        }
        return candidate.id.uuidString < subject.id.uuidString
    }

    private static let japaneseLocale = Locale(identifier: "ja_JP")
    private static let titleWhitespace = CharacterSet.whitespacesAndNewlines

    static func normalize(_ title: String) -> String {
        let trimmed: String
        if let first = title.unicodeScalars.first,
           let last = title.unicodeScalars.last,
           !titleWhitespace.contains(first),
           !titleWhitespace.contains(last) {
            trimmed = title
        } else {
            trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !needsFold(trimmed) { return trimmed }
        return trimmed.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: japaneseLocale
        )
    }

    /// 大文字・全角英数・半角カナが無い題名は、畳み込んでも同じ文字列になる。
    private static func needsFold(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value < 0x80 {
                if value >= 0x41, value <= 0x5A { return true }
                continue
            }
            if value >= 0x3040, value <= 0x30FF { continue }
            if value >= 0x4E00, value <= 0x9FFF { continue }
            return true
        }
        return false
    }
}
