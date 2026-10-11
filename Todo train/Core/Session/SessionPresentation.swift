//
//  SessionPresentation.swift
//  Todo train
//
//  Ephemeral UI projection owned by SessionManager. Not store truth and not a
//  score. Write commands stay on SessionManager; Views read this for chrome.
//

import Foundation
import Observation

@Observable
@MainActor
final class SessionPresentation {
    /// Arrival / 定時運行 moments. Cleared by overlay consume.
    var punctualityQueue: [PunctualityMoment] = []
    /// Bumps when a 定時運行 moment is enqueued (haptic). Consume must not tick.
    var punctualityHapticTick: Int = 0
    /// Bumps when a 車内放送 panel appears.
    var checkInHapticTick: Int = 0
    /// Shown in the 停車中 block after ATS. Cleared on 再乗車 / 発車.
    var timetableQuietMessage: String?

    var punctualityMoment: PunctualityMoment? { punctualityQueue.first }

    func enqueuePunctualityMoment(_ moment: PunctualityMoment) {
        punctualityQueue.append(moment)
        // Arrival haptic is owned by ArrivalInvalidateOverlay (user swipe).
        // 定時運行 keeps a brief success cue on enqueue.
        if case .onTimeService = moment.kind {
            punctualityHapticTick += 1
        }
    }

    func consumePunctualityMoment() {
        guard !punctualityQueue.isEmpty else { return }
        punctualityQueue.removeFirst()
    }

    /// Drop arrival celebrations when another ride starts.
    func consumeArrivalCelebrations() {
        punctualityQueue.removeAll { moment in
            if case .arrival = moment.kind { return true }
            return false
        }
    }

    func clearTimetableQuietMessage() {
        timetableQuietMessage = nil
    }

    func noteCheckInHaptic() {
        checkInHapticTick += 1
    }
}
