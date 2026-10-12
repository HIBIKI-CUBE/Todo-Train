//
//  SessionManager+ArrivalGap.swift
//  Todo train
//
//  After the arrival stamp, two short notices. They do not extend the ride.
//

import AudioToolbox
import Foundation
import SwiftData
import TodoTrainSync
#if canImport(UIKit)
import UIKit
#endif

struct ArrivalGapBannerState: Equatable {
    var prompt: String
    var holdLamp: Bool
    var ticketID: UUID?
}

extension SessionManager {
    func noteArrivalGapSurface(hubVisible: Bool, arrivalScreenOpen: Bool) {
        let changed = iphoneHubVisible != hubVisible || self.arrivalScreenOpen != arrivalScreenOpen
        iphoneHubVisible = hubVisible
        self.arrivalScreenOpen = arrivalScreenOpen
        guard changed else { return }
        syncArrivalGap(now: clock.now)
    }

    func dismissArrivalGap() {
        _ = dismissArrivalGapIfShowing(now: clock.now)
    }

    /// Mac `still` during the blank. Idle cabin stays for its own notice.
    @discardableResult
    func dismissArrivalGapIfShowing(now: Date) -> Bool {
        guard let anchor = gapAnchorSession(now: now) else { return false }
        guard !anchor.nudgeFiredStagesRaw.contains(ArrivalGapDeciding.dismissMarker) else { return false }
        let decision = gapDecision(anchor: anchor, now: now)
        guard decision.visible != nil else { return false }
        anchor.nudgeFiredStagesRaw.append(ArrivalGapDeciding.dismissMarker)
        arrivalGapBanner = nil
        cancelGapWatch()
        bumpCompanionSync()
        _ = saveBestEffort()
        return true
    }

    func boardReservedFromHub() throws {
        guard let ticketID = arrivalGapBanner?.ticketID, let ticket = fetchTicket(id: ticketID) else {
            return
        }
        try board(ticket: ticket)
    }

    func syncArrivalGap(now: Date) {
        guard let anchor = gapAnchorSession(now: now) else {
            let hadBanner = arrivalGapBanner != nil
            arrivalGapBanner = nil
            cancelGapWatch()
            if hadBanner { bumpCompanionSync() }
            return
        }
        let before = anchor.nudgeFiredStagesRaw
        let decision = gapDecision(anchor: anchor, now: now)
        for item in decision.newlyDue where !anchor.nudgeFiredStagesRaw.contains(item.stage.rawValue) {
            anchor.nudgeFiredStagesRaw.append(item.stage.rawValue)
            let fresh = now.timeIntervalSince(item.fireAt) <= ArrivalGapDeciding.fresh
            if fresh, item.rings, item.surface == .iphone, iphoneHubVisible {
                playGapCue()
            }
        }
        let banner = decision.banner(ticketID: reservedNextTicket()?.id)
        let changed = before != anchor.nudgeFiredStagesRaw || arrivalGapBanner != banner
        arrivalGapBanner = banner
        if changed {
            bumpCompanionSync()
            _ = saveBestEffort()
        }
        armGapWatch(at: decision.wakeAt)
    }

    func arrivalGapSnapFields(now: Date, reserved: WireReservedTicket?) -> NudgeSnapFields {
        guard let anchor = gapAnchorSession(now: now) else {
            return NudgeSnapFields(nudge: nil, plan: nil, reserved: reserved, pendingCabin: nil)
        }
        let decision = gapDecision(anchor: anchor, now: now)
        guard let visible = decision.visible else {
            return NudgeSnapFields(nudge: nil, plan: nil, reserved: reserved, pendingCabin: nil)
        }
        let ringSurface: NudgeRingSurface = visible.rings
            ? NudgeRingSurface(rawValue: visible.surface.rawValue)
            : .none
        let nudge = WireNudge(
            id: NudgeSession.id(sessionID: anchor.id, stageRaw: visible.stage.rawValue),
            kind: .gap,
            stage: NudgeStageWire(visible.stage),
            ringSurface: ringSurface,
            firedAt: Int(visible.fireAt.timeIntervalSince1970)
        )
        let plan = decision.upcoming.map { item in
            WireNudgePlanItem(
                stage: NudgeStageWire(item.stage),
                fireAt: Int(item.fireAt.timeIntervalSince1970),
                surface: NudgeRingSurface(rawValue: item.surface.rawValue),
                rings: item.rings
            )
        }
        return NudgeSnapFields(
            nudge: nudge,
            plan: plan.isEmpty ? nil : plan,
            reserved: reserved,
            pendingCabin: .gap
        )
    }

    func clearArrivalGapWatch() {
        cancelGapWatch()
        if arrivalGapBanner != nil {
            arrivalGapBanner = nil
        }
    }

    private func gapAnchorSession(now: Date) -> WorkSession? {
        _ = now
        guard activeServiceDay?.isOpen == true else { return nil }
        guard !hasOpenRide(), fetchOpenPassengerRide() == nil else { return nil }
        guard let anchor = latestStampedArrival(), let stamp = anchor.arrivalStampedAt else { return nil }
        if rideStarted(after: stamp, otherThan: anchor.id) { return nil }
        return anchor
    }

    private func gapDecision(anchor: WorkSession, now: Date) -> ArrivalGapDecision {
        let fired = Set(anchor.nudgeFiredStagesRaw.compactMap(NudgeGap.init(rawValue:)))
        return ArrivalGapDeciding.decide(
            stampedAt: anchor.arrivalStampedAt,
            now: now,
            arrivalScreenOpen: arrivalScreenOpen,
            blocked: false,
            dismissed: anchor.nudgeFiredStagesRaw.contains(ArrivalGapDeciding.dismissMarker),
            cabinEnabled: settings.cabinAnnouncementsEnabled,
            fired: fired,
            foreground: gapForeground,
            macAttending: macAttending,
            reservedTitle: reservedNextTicket()?.title,
            calendar: calendar
        )
    }

    private var gapForeground: [NudgeSurface] {
        var devices: [NudgeSurface] = []
        if iphoneHubVisible { devices.append(.iphone) }
        if macPipVisible { devices.append(.mac) }
        return devices
    }

    private func latestStampedArrival() -> WorkSession? {
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        return sessions
            .filter { $0.arrivalStampedAt != nil }
            .max { ($0.arrivalStampedAt ?? .distantPast) < ($1.arrivalStampedAt ?? .distantPast) }
    }

    private func rideStarted(after stamp: Date, otherThan sessionID: UUID) -> Bool {
        let sessions = (try? modelContext.fetch(FetchDescriptor<WorkSession>())) ?? []
        return sessions.contains { $0.id != sessionID && $0.startedAt > stamp }
    }

    private func playGapCue() {
        gapCueTick += 1
        #if canImport(UIKit)
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func armGapWatch(at date: Date?) {
        cancelGapWatch()
        guard let date, clock is SystemSessionClock else { return }
        gapWatchTask = Task { @MainActor [weak self] in
            let delay = date.timeIntervalSince(self?.clock.now ?? Date())
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    private func cancelGapWatch() {
        gapWatchTask?.cancel()
        gapWatchTask = nil
    }
}

extension ArrivalGapDecision {
    fileprivate func banner(ticketID: UUID?) -> ArrivalGapBannerState? {
        guard visible != nil, let prompt else { return nil }
        let lamp = visible?.surface == .iphone && visible?.rings == true
        return ArrivalGapBannerState(prompt: prompt, holdLamp: lamp, ticketID: ticketID)
    }
}
