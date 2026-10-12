import Foundation

/// Who posts the safety-net notification. Absent on snaps from before contract 11.
public enum NotifyOn: String, Codable, Sendable, Equatable {
    case iphone
    case mac
    case none
}

public struct SnapPlaintext: Codable, Equatable, Sendable {
    public var rev: Int
    public var sessionId: UUID?
    public var ticketId: UUID?
    public var title: String?
    public var phase: WirePhase
    public var startedAt: Int?
    public var estimatedSeconds: Int?
    public var pausedAccumulated: Int?
    public var pausedAt: Int?
    public var boardedDeviceID: String?
    public var serviceActive: Bool
    public var cabinEnabled: Bool
    public var checkInFiredCount: Int
    public var pendingCabin: CabinKind?
    public var nextBlockTitle: String?
    public var nextBlockStartsAt: Int?
    public var nextBlockEndsAt: Int?
    public var timetablePauseAt: Int?
    /// Sender's build. Absent on older iPhones.
    public var build: WireBuildInfo?
    /// Sender's contract. Absent on peers that predate the announcement (those are v3).
    public var contract: Int?
    public var minReadable: Int?
    /// The nudge on screen now. Absent on older snaps.
    public var nudge: WireNudge?
    /// Stages that have not been reached. Absent on older snaps.
    public var nudgePlan: [WireNudgePlanItem]?
    /// Ticket that can board after arrival. Absent when there is none.
    public var reserved: WireReservedTicket?
    /// Reason for the open pause. Present only while `phase` is `paused`.
    public var pauseHeldBy: PauseHeldBy?
    /// Which device posts the safety-net. Absent means an older iPhone.
    public var notifyOn: NotifyOn?
    /// Turn inside the 4-ring cap. Present with `notifyOn` when a post is assigned.
    public var notifyTurn: Int?
    /// Unix seconds for Mac's away or idle notification. Overtime is computed from the ride.
    public var notifyFireAt: Int?

    public init(
        rev: Int,
        sessionId: UUID?,
        ticketId: UUID?,
        title: String?,
        phase: WirePhase,
        startedAt: Int?,
        estimatedSeconds: Int?,
        pausedAccumulated: Int?,
        pausedAt: Int?,
        boardedDeviceID: String?,
        serviceActive: Bool = false,
        cabinEnabled: Bool = true,
        checkInFiredCount: Int = 0,
        pendingCabin: CabinKind? = nil,
        nextBlockTitle: String? = nil,
        nextBlockStartsAt: Int? = nil,
        nextBlockEndsAt: Int? = nil,
        timetablePauseAt: Int? = nil,
        build: WireBuildInfo? = nil,
        contract: Int? = nil,
        minReadable: Int? = nil,
        nudge: WireNudge? = nil,
        nudgePlan: [WireNudgePlanItem]? = nil,
        reserved: WireReservedTicket? = nil,
        pauseHeldBy: PauseHeldBy? = nil,
        notifyOn: NotifyOn? = nil,
        notifyTurn: Int? = nil,
        notifyFireAt: Int? = nil
    ) {
        self.rev = rev
        self.sessionId = sessionId
        self.ticketId = ticketId
        self.title = title
        self.phase = phase
        self.startedAt = startedAt
        self.estimatedSeconds = estimatedSeconds
        self.pausedAccumulated = pausedAccumulated
        self.pausedAt = pausedAt
        self.boardedDeviceID = boardedDeviceID
        self.serviceActive = serviceActive
        self.cabinEnabled = cabinEnabled
        self.checkInFiredCount = checkInFiredCount
        self.pendingCabin = pendingCabin
        self.nextBlockTitle = nextBlockTitle
        self.nextBlockStartsAt = nextBlockStartsAt
        self.nextBlockEndsAt = nextBlockEndsAt
        self.timetablePauseAt = timetablePauseAt
        self.build = build
        self.contract = contract
        self.minReadable = minReadable
        self.nudge = nudge
        self.nudgePlan = nudgePlan
        self.reserved = reserved
        self.pauseHeldBy = phase == .paused ? pauseHeldBy : nil
        self.notifyOn = notifyOn
        self.notifyTurn = notifyTurn
        self.notifyFireAt = notifyFireAt
    }

    public var announcement: ContractAnnouncement {
        .resolved(contract: contract, minReadable: minReadable)
    }

    enum CodingKeys: String, CodingKey {
        case rev, sessionId, ticketId, title, phase
        case startedAt, estimatedSeconds, pausedAccumulated, pausedAt, boardedDeviceID
        case serviceActive, cabinEnabled, checkInFiredCount, pendingCabin
        case nextBlockTitle, nextBlockStartsAt, nextBlockEndsAt, timetablePauseAt, build
        case contract, minReadable
        case nudge, nudgePlan, reserved, pauseHeldBy
        case notifyOn, notifyTurn, notifyFireAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rev = try container.decode(Int.self, forKey: .rev)
        sessionId = try container.decodeLowercaseUUIDIfPresent(.sessionId)
        ticketId = try container.decodeLowercaseUUIDIfPresent(.ticketId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        phase = try container.decode(WirePhase.self, forKey: .phase)
        startedAt = try container.decodeIfPresent(Int.self, forKey: .startedAt)
        estimatedSeconds = try container.decodeIfPresent(Int.self, forKey: .estimatedSeconds)
        pausedAccumulated = try container.decodeIfPresent(Int.self, forKey: .pausedAccumulated)
        pausedAt = try container.decodeIfPresent(Int.self, forKey: .pausedAt)
        boardedDeviceID = try container.decodeIfPresent(String.self, forKey: .boardedDeviceID)
        serviceActive = try container.decodeIfPresent(Bool.self, forKey: .serviceActive) ?? false
        cabinEnabled = try container.decodeIfPresent(Bool.self, forKey: .cabinEnabled) ?? true
        checkInFiredCount = try container.decodeIfPresent(Int.self, forKey: .checkInFiredCount) ?? 0
        if container.contains(.pendingCabin) {
            if try container.decodeNil(forKey: .pendingCabin) {
                pendingCabin = nil
            } else {
                pendingCabin = try container.decode(CabinKind.self, forKey: .pendingCabin)
            }
        } else {
            pendingCabin = nil
        }
        nextBlockTitle = try container.decodeIfPresent(String.self, forKey: .nextBlockTitle)
        nextBlockStartsAt = try container.decodeIfPresent(Int.self, forKey: .nextBlockStartsAt)
        nextBlockEndsAt = try container.decodeIfPresent(Int.self, forKey: .nextBlockEndsAt)
        timetablePauseAt = try container.decodeIfPresent(Int.self, forKey: .timetablePauseAt)
        build = WireBuildInfo.decodeLenient(from: container, forKey: .build)
        contract = ContractKeyDecoding.positiveInt(container, .contract)
        minReadable = ContractKeyDecoding.positiveInt(container, .minReadable)
        nudge = Self.lenient(WireNudge.self, from: container, forKey: .nudge)
        nudgePlan = Self.lenient([WireNudgePlanItem].self, from: container, forKey: .nudgePlan)
        reserved = Self.lenient(WireReservedTicket.self, from: container, forKey: .reserved)
        let decodedPauseHeldBy = try container.decodeIfPresent(PauseHeldBy.self, forKey: .pauseHeldBy)
        pauseHeldBy = phase == .paused ? decodedPauseHeldBy : nil
        if let raw = try container.decodeIfPresent(String.self, forKey: .notifyOn) {
            notifyOn = NotifyOn(rawValue: raw)
        } else {
            notifyOn = nil
        }
        notifyTurn = try container.decodeIfPresent(Int.self, forKey: .notifyTurn)
        notifyFireAt = try container.decodeIfPresent(Int.self, forKey: .notifyFireAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(rev, forKey: .rev)
        try container.encodeLowercaseUUID(sessionId, forKey: .sessionId)
        try container.encodeLowercaseUUID(ticketId, forKey: .ticketId)
        try container.encode(title, forKey: .title)
        try container.encode(phase, forKey: .phase)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(estimatedSeconds, forKey: .estimatedSeconds)
        try container.encode(pausedAccumulated, forKey: .pausedAccumulated)
        try container.encode(pausedAt, forKey: .pausedAt)
        try container.encode(boardedDeviceID, forKey: .boardedDeviceID)
        try container.encode(serviceActive, forKey: .serviceActive)
        try container.encode(cabinEnabled, forKey: .cabinEnabled)
        try container.encode(checkInFiredCount, forKey: .checkInFiredCount)
        try container.encode(pendingCabin, forKey: .pendingCabin)
        try container.encodeIfPresent(nextBlockTitle, forKey: .nextBlockTitle)
        try container.encodeIfPresent(nextBlockStartsAt, forKey: .nextBlockStartsAt)
        try container.encodeIfPresent(nextBlockEndsAt, forKey: .nextBlockEndsAt)
        try container.encodeIfPresent(timetablePauseAt, forKey: .timetablePauseAt)
        try container.encodeIfPresent(build, forKey: .build)
        try container.encodeIfPresent(contract, forKey: .contract)
        try container.encodeIfPresent(minReadable, forKey: .minReadable)
        try container.encodeIfPresent(nudge, forKey: .nudge)
        try container.encodeIfPresent(nudgePlan, forKey: .nudgePlan)
        try container.encodeIfPresent(reserved, forKey: .reserved)
        if phase == .paused {
            try container.encodeIfPresent(pauseHeldBy, forKey: .pauseHeldBy)
        }
        try container.encodeIfPresent(notifyOn, forKey: .notifyOn)
        try container.encodeIfPresent(notifyTurn, forKey: .notifyTurn)
        try container.encodeIfPresent(notifyFireAt, forKey: .notifyFireAt)
    }

    /// A broken optional field is dropped. The rest of the snap still decodes.
    private static func lenient<T: Decodable, K: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> T? {
        guard container.contains(key) else { return nil }
        if (try? container.decodeNil(forKey: key)) == true { return nil }
        return try? container.decode(T.self, forKey: key)
    }

    /// Remaining seconds using the contract formula. Idle / missing fields → nil.
    public func remainingSeconds(at now: Int) -> Int? {
        guard let startedAt, let estimatedSeconds else { return nil }
        let pausedTotal =
            (pausedAccumulated ?? 0)
            + (pausedAt.map { now - $0 } ?? 0)
        let elapsedActive = now - startedAt - pausedTotal
        return estimatedSeconds - elapsedActive
    }

    /// Active elapsed seconds. Idle / missing fields → nil.
    public func elapsedActiveSeconds(at now: Int) -> Int? {
        guard let estimated = estimatedSeconds, let remaining = remainingSeconds(at: now) else {
            return nil
        }
        return estimated - remaining
    }
}

extension KeyedEncodingContainer where K: CodingKey {
    mutating func encodeLowercaseUUID(_ value: UUID?, forKey key: K) throws {
        if let value {
            try encode(value.canonicalLowercase, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }

    mutating func encodeIfPresentLowercaseUUID(_ value: UUID?, forKey key: K) throws {
        if let value {
            try encode(value.canonicalLowercase, forKey: key)
        }
    }
}

extension KeyedDecodingContainer where K: CodingKey {
    func decodeLowercaseUUIDIfPresent(_ key: K) throws -> UUID? {
        guard contains(key) else { return nil }
        if try decodeNil(forKey: key) { return nil }
        let raw = try decode(String.self, forKey: key)
        guard let uuid = UUID(uuidString: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: self,
                debugDescription: "Invalid UUID"
            )
        }
        return uuid
    }
}
