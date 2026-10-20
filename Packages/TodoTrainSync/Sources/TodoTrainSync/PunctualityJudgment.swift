import Foundation

/// On-time judgment, home band, signal, and seal tier from ride records only.
public enum PunctualityJudgment: Sendable {
    public static let bandRatio: Double = 0.15
    public static let minimumBandSeconds: TimeInterval = 60
    /// Running seconds before arrival a committed reestimate must land to count.
    public static let reestimateLeadSeconds: TimeInterval = 300
    public static let lateGraceSeconds: TimeInterval = 0.5
    /// 運転調整で定時に着いたときの判の上限（発券時の 1.0 より必ず下）。
    public static let adjustCeiling: Double = 0.9

    public enum Outcome: String, Equatable, Sendable {
        case onTime
        case early
        case late
        case notApplicable
    }

    public enum JudgedEstimateSource: Equatable, Sendable {
        case original
        case reestimate(index: Int)
    }

    /// Export wire value for `judgedEstimateSource`.
    public enum JudgedEstimateSourceWire: String, Equatable, Sendable, Encodable {
        case original
        case reestimate
    }

    public struct JudgedEstimateSourceExport: Equatable, Sendable, Encodable {
        public var kind: JudgedEstimateSourceWire
        /// Set when `kind == .reestimate`.
        public var reestimateIndex: Int?

        public init(kind: JudgedEstimateSourceWire, reestimateIndex: Int? = nil) {
            self.kind = kind
            self.reestimateIndex = reestimateIndex
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            if kind == .reestimate {
                try container.encode(reestimateIndex, forKey: .reestimateIndex)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case reestimateIndex
        }
    }

    public enum ArrivalJudgementExport: String, Equatable, Sendable, Encodable {
        case onTime
        case none
    }

    public enum OnTimeSealTier: String, Equatable, Sendable {
        case ticketing
        case earlyReestimate
        case lateReestimate
    }

    public enum HomeSignalState: Equatable, Sendable {
        case green
        case yellow
        case off
    }

    public enum StampSeason: String, Equatable, Sendable {
        case spring
        case summer
        case autumn
        case winter
    }

    public enum StampTimeOfDay: String, Equatable, Sendable {
        case morning
        case afternoon
        case evening
        case night
    }

    public struct ReestimateCommit: Equatable, Sendable {
        public var reestimateIndex: Int
        public var activeSeconds: TimeInterval
        public var committedRemainingSeconds: Int

        public init(
            reestimateIndex: Int,
            activeSeconds: TimeInterval,
            committedRemainingSeconds: Int
        ) {
            self.reestimateIndex = reestimateIndex
            self.activeSeconds = activeSeconds
            self.committedRemainingSeconds = committedRemainingSeconds
        }
    }

    public struct RideInput: Equatable, Sendable {
        public var arrived: Bool
        public var activeSeconds: TimeInterval
        public var estimatedSecondsAtStart: Int
        public var reestimates: [ReestimateCommit]

        public init(
            arrived: Bool,
            activeSeconds: TimeInterval,
            estimatedSecondsAtStart: Int,
            reestimates: [ReestimateCommit] = []
        ) {
            self.arrived = arrived
            self.activeSeconds = activeSeconds
            self.estimatedSecondsAtStart = estimatedSecondsAtStart
            self.reestimates = reestimates
        }
    }

    public struct Judgment: Equatable, Sendable {
        public var source: JudgedEstimateSource
        public var judgedTotalSeconds: TimeInterval
        public var bandHalfWidth: TimeInterval
        public var lowerBound: TimeInterval
        public var upperBound: TimeInterval
        public var outcome: Outcome
        /// 定時に着いたときだけ。走行中の見本・到着の角判はこの値（または nil）。
        public var sealLuxury: Double?
        public var signal: HomeSignalState
        public var exportSource: JudgedEstimateSourceExport
        public var arrivalJudgement: ArrivalJudgementExport

        public init(
            source: JudgedEstimateSource,
            judgedTotalSeconds: TimeInterval,
            bandHalfWidth: TimeInterval,
            lowerBound: TimeInterval,
            upperBound: TimeInterval,
            outcome: Outcome,
            sealLuxury: Double?,
            signal: HomeSignalState,
            exportSource: JudgedEstimateSourceExport,
            arrivalJudgement: ArrivalJudgementExport
        ) {
            self.source = source
            self.judgedTotalSeconds = judgedTotalSeconds
            self.bandHalfWidth = bandHalfWidth
            self.lowerBound = lowerBound
            self.upperBound = upperBound
            self.outcome = outcome
            self.sealLuxury = sealLuxury
            self.signal = signal
            self.exportSource = exportSource
            self.arrivalJudgement = arrivalJudgement
        }

        /// 角判の描画がまだ段を使うときの互換（#171 まで）。
        public var legacySealTier: OnTimeSealTier? {
            sealLuxury.map { PunctualityJudgment.legacySealTier(luxury: $0) }
        }
    }

    public static func judge(_ input: RideInput) -> Judgment {
        let elapsed = max(0, input.activeSeconds)
        let arrived = input.arrived
        let sorted = input.reestimates.sorted { $0.reestimateIndex < $1.reestimateIndex }

        let arrivalSource = selectJudgedSource(
            arrivalActiveSeconds: elapsed,
            estimatedSecondsAtStart: input.estimatedSecondsAtStart,
            reestimates: sorted
        )
        let homeSource = homeJudgedSource(
            at: elapsed,
            estimatedSecondsAtStart: input.estimatedSecondsAtStart,
            reestimates: sorted
        )

        let judgedTotal = totalSeconds(
            source: arrived ? arrivalSource : homeSource,
            estimatedSecondsAtStart: input.estimatedSecondsAtStart,
            reestimates: sorted
        )
        let bandBasis = bandBasisSeconds(
            source: arrived ? arrivalSource : homeSource,
            estimatedSecondsAtStart: input.estimatedSecondsAtStart,
            reestimates: sorted
        )
        let half = bandHalfWidth(bandBasisSeconds: bandBasis)
        let lower = judgedTotal - half
        let upper = judgedTotal + half

        let outcome: Outcome = {
            guard arrived else { return .notApplicable }
            if elapsed < lower { return .early }
            if elapsed > upper + lateGraceSeconds { return .late }
            return .onTime
        }()

        let sealLuxury: Double? = {
            guard outcome == .onTime else { return nil }
            return Self.sealLuxury(source: arrivalSource, reestimates: sorted)
        }()

        let signal = signalState(elapsed: elapsed, lowerBound: lower, upperBound: upper)
        let exportSource = exportSource(arrivalSource)
        let arrivalJudgement: ArrivalJudgementExport = outcome == .onTime ? .onTime : .none

        return Judgment(
            source: arrived ? arrivalSource : homeSource,
            judgedTotalSeconds: judgedTotal,
            bandHalfWidth: half,
            lowerBound: lower,
            upperBound: upper,
            outcome: outcome,
            sealLuxury: sealLuxury,
            signal: signal,
            exportSource: exportSource,
            arrivalJudgement: arrivalJudgement
        )
    }

    public static func bandHalfWidth(bandBasisSeconds: Int) -> TimeInterval {
        let basis = TimeInterval(max(bandBasisSeconds, 1))
        return max(basis * bandRatio, minimumBandSeconds)
    }

    public static func signalState(
        elapsed: TimeInterval,
        lowerBound: TimeInterval,
        upperBound: TimeInterval
    ) -> HomeSignalState {
        if elapsed < lowerBound { return .green }
        if elapsed <= upperBound { return .yellow }
        return .off
    }

    public static func stampSeason(at date: Date, timeZone: TimeZone = tokyoTimeZone) -> StampSeason {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let month = calendar.component(.month, from: date)
        switch month {
        case 3...5: return .spring
        case 6...8: return .summer
        case 9...11: return .autumn
        default: return .winter
        }
    }

    public static func stampTimeOfDay(at date: Date, timeZone: TimeZone = tokyoTimeZone) -> StampTimeOfDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<11: return .morning
        case 11..<17: return .afternoon
        case 17..<21: return .evening
        default: return .night
        }
    }

    public static let tokyoTimeZone = TimeZone(identifier: "Asia/Tokyo")!

    /// 定時判定に使った見積もりから判の豪華さ（0…1、0.01 刻み）。運任せなし。
    public static func sealLuxury(
        source: JudgedEstimateSource,
        reestimates: [ReestimateCommit]
    ) -> Double {
        switch source {
        case .original:
            return 1.0
        case .reestimate(let index):
            guard let event = reestimates.first(where: { $0.reestimateIndex == index }) else {
                return 1.0
            }
            let active = max(0, event.activeSeconds)
            let total = active + TimeInterval(max(0, event.committedRemainingSeconds))
            if total <= 0 { return 0.0 }
            let ratio = min(max(active / total, 0), 1)
            let raw = adjustCeiling * (1 - ratio)
            return roundSealLuxury(raw)
        }
    }

    /// export の `onTimeSealTier` 互換（豪華さから段の識別子を導く）。
    public static func legacyTier(luxury: Double) -> String {
        if luxury == 1.0 { return OnTimeSealTier.ticketing.rawValue }
        if luxury >= 0.45 { return OnTimeSealTier.earlyReestimate.rawValue }
        return OnTimeSealTier.lateReestimate.rawValue
    }

    /// 描画・読み上げがまだ段を使うときの互換（#171 まで）。
    public static func legacySealTier(luxury: Double) -> OnTimeSealTier {
        OnTimeSealTier(rawValue: legacyTier(luxury: luxury)) ?? .lateReestimate
    }

    private static func roundSealLuxury(_ raw: Double) -> Double {
        (raw * 100).rounded() / 100
    }

    // MARK: - Internals

    private static func selectJudgedSource(
        arrivalActiveSeconds: TimeInterval,
        estimatedSecondsAtStart: Int,
        reestimates: [ReestimateCommit]
    ) -> JudgedEstimateSource {
        guard let last = eligibleReestimates(
            beforeArrivalActiveSeconds: arrivalActiveSeconds,
            reestimates: reestimates
        ).last else {
            return .original
        }
        return .reestimate(index: last.reestimateIndex)
    }

    private static func homeJudgedSource(
        at elapsed: TimeInterval,
        estimatedSecondsAtStart: Int,
        reestimates: [ReestimateCommit]
    ) -> JudgedEstimateSource {
        var source: JudgedEstimateSource = .original
        var total = TimeInterval(max(estimatedSecondsAtStart, 0))
        var frozen = false

        for event in reestimates {
            guard elapsed >= event.activeSeconds else { continue }
            if frozen { break }
            source = .reestimate(index: event.reestimateIndex)
            total = event.activeSeconds + TimeInterval(event.committedRemainingSeconds)
            if total - elapsed <= reestimateLeadSeconds {
                frozen = true
            }
        }
        return source
    }

    private static func eligibleReestimates(
        beforeArrivalActiveSeconds: TimeInterval,
        reestimates: [ReestimateCommit]
    ) -> [ReestimateCommit] {
        reestimates.filter {
            beforeArrivalActiveSeconds - $0.activeSeconds >= reestimateLeadSeconds
        }
    }

    private static func totalSeconds(
        source: JudgedEstimateSource,
        estimatedSecondsAtStart: Int,
        reestimates: [ReestimateCommit]
    ) -> TimeInterval {
        switch source {
        case .original:
            return TimeInterval(max(estimatedSecondsAtStart, 0))
        case .reestimate(let index):
            guard let event = reestimates.first(where: { $0.reestimateIndex == index }) else {
                return TimeInterval(max(estimatedSecondsAtStart, 0))
            }
            return event.activeSeconds + TimeInterval(event.committedRemainingSeconds)
        }
    }

    private static func bandBasisSeconds(
        source: JudgedEstimateSource,
        estimatedSecondsAtStart: Int,
        reestimates: [ReestimateCommit]
    ) -> Int {
        switch source {
        case .original:
            return max(estimatedSecondsAtStart, 1)
        case .reestimate(let index):
            guard let event = reestimates.first(where: { $0.reestimateIndex == index }) else {
                return max(estimatedSecondsAtStart, 1)
            }
            return max(event.committedRemainingSeconds, 1)
        }
    }

    private static func exportSource(_ source: JudgedEstimateSource) -> JudgedEstimateSourceExport {
        switch source {
        case .original:
            return JudgedEstimateSourceExport(kind: .original)
        case .reestimate(let index):
            return JudgedEstimateSourceExport(kind: .reestimate, reestimateIndex: index)
        }
    }
}
