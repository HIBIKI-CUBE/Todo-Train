import Foundation

public struct CabinInterrupt: Equatable, Sendable {
    public var kind: CabinKind?
    public var delivery: CabinDelivery
    public var prompt: String?
    public var isDue: Bool

    public static let idle = CabinInterrupt(
        kind: nil,
        delivery: .ignore,
        prompt: nil,
        isDue: false
    )

    public init(kind: CabinKind?, delivery: CabinDelivery, prompt: String?, isDue: Bool) {
        self.kind = kind
        self.delivery = delivery
        self.prompt = prompt
        self.isDue = isDue
    }

    public var showsPip: Bool { isDue && delivery == .pip }
    public var showsNotification: Bool { isDue && delivery == .notification }
}

/// Mac-side watch. Progress may use local offsets. Idle is due only when snap already has pending.
public enum CabinInterruptWatch: Sendable {
    public static func evaluate(
        snap: SnapPlaintext?,
        now: Int,
        localEnabled: Bool,
        optimisticFiredCount: Int,
        optimisticIdleConsumed: Bool = false
    ) -> CabinInterrupt {
        guard let snap, localEnabled, snap.cabinEnabled else { return .idle }
        let hasRide: Bool
        switch snap.phase {
        case .running, .paused, .overtime:
            hasRide = snap.sessionId != nil
        case .idle, .unknown:
            hasRide = false
        }

        if snap.pendingCabin == .idle {
            if optimisticIdleConsumed || !snap.serviceActive {
                return .idle
            }
            return CabinInterrupt(
                kind: .idle,
                delivery: CabinDelivery.surface(kind: .idle, hasRide: hasRide),
                prompt: CabinCopy.idle,
                isDue: true
            )
        }

        if snap.pendingCabin == .away {
            return CabinInterrupt(
                kind: .away,
                delivery: .ignore,
                prompt: nil,
                isDue: false
            )
        }

        if optimisticFiredCount > snap.checkInFiredCount {
            return .idle
        }

        let progressDue = isProgressDue(snap: snap, now: now, firedCount: snap.checkInFiredCount)
        guard progressDue else { return .idle }
        return CabinInterrupt(
            kind: .progress,
            delivery: CabinDelivery.surface(kind: .progress, hasRide: hasRide),
            prompt: CabinCopy.prompt,
            isDue: true
        )
    }

    /// Mac never schedules idle. Due only when iPhone already put `pendingCabin=idle` on the snap.
    public static func isIdleSchedulerDue(serviceActive: Bool, pendingCabin: CabinKind?) -> Bool {
        serviceActive && pendingCabin == .idle
    }

    private static func isProgressDue(snap: SnapPlaintext, now: Int, firedCount: Int) -> Bool {
        if snap.pendingCabin == .progress { return true }
        guard snap.phase == .running, let sessionId = snap.sessionId else { return false }
        let remaining = TimeInterval(snap.remainingSeconds(at: now) ?? 0)
        let elapsed = TimeInterval(snap.elapsedActiveSeconds(at: now) ?? 0)
        let offsets = CabinBroadcastScheduling.offsets(
            estimatedSeconds: snap.estimatedSeconds ?? 0,
            seed: sessionId
        )
        return CabinBroadcastScheduling.dueProgressOffset(
            offsets: offsets,
            firedCount: firedCount,
            elapsedSeconds: elapsed,
            remainingSeconds: remaining,
            hasPending: false
        ) != nil
    }
}
