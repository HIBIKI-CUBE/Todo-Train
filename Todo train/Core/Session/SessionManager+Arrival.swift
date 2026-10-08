//
//  SessionManager+Arrival.swift
//  Todo train
//
//  検札は到着の締め。発車も延長もしない。
//

import Foundation
import SwiftData

extension SessionManager {
    /// 検札印。行き先と時刻だけを残し、次の乗車は始めない。
    func recordArrivalStamp(sessionID: UUID, action: ArrivalAction, now: Date? = nil) throws {
        let now = now ?? clock.now
        guard let session = fetchWorkSession(id: sessionID), session.outcome == .arrived else {
            throw SessionError.noActiveSession
        }
        session.arrivalAction = action
        session.arrivalStampedAt = now
        try save()
    }

    /// 到着画面の即時切符。発行だけ行い、発車しない。
    @discardableResult
    func issueArrivalInstant(title: String, minutes: Int) throws -> Ticket {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SessionError.emptyTicketTitle
        }
        let clamped = AppSettings.clampEstimateMinutes(minutes)
        let ticket = try TicketIssuer.issue(title: trimmed, minutes: clamped, into: modelContext)
        settings.lastIssuedEstimateMinutes = clamped
        return ticket
    }

    /// 別経路で乗車が始まったら、残っている到着祝祭を閉じる。
    func consumeArrivalCelebrations() {
        punctualityQueue.removeAll { moment in
            if case .arrival = moment.kind { return true }
            return false
        }
    }

    func fetchWorkSession(id: UUID) -> WorkSession? {
        let target = id
        var descriptor = FetchDescriptor<WorkSession>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first
    }
}
