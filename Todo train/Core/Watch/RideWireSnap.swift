//
//  RideWireSnap.swift
//  Todo train
//

import Foundation
import TodoTrainSync

/// The snap the iPhone already sends to the Mac, stamped for the Watch copy.
enum RideWireSnap {
    static func make(
        sessionManager: SessionManager,
        settings: AppSettings,
        rev: Int,
        now: Date
    ) -> SnapPlaintext {
        let nudge = sessionManager.nudgeSnapFields(now: now)
        let fit = sessionManager.timetableFit()
        let visible = fit.visibleOccupancy
        var plaintext = CompanionSnapBuilding.snap(
            rev: rev,
            phase: sessionManager.phase,
            session: sessionManager.activeSession,
            now: now,
            serviceActive: sessionManager.activeServiceDay?.isOpen == true,
            cabinEnabled: settings.cabinAnnouncementsEnabled,
            pendingCabin: sessionManager.activeServiceDay?.pendingCabin?.cabin,
            nextBlockTitle: visible?.title,
            nextBlockStartsAt: visible.map { Int($0.startsAt.timeIntervalSince1970) },
            nextBlockEndsAt: visible.map { Int($0.endsAt.timeIntervalSince1970) },
            // Older Macs paused when this field arrived. Overlap does not publish a pause time.
            timetablePauseAt: nil,
            nudge: nudge.nudge,
            nudgePlan: nudge.plan,
            reserved: nudge.reserved,
            openPendingCabin: nudge.pendingCabin
        )
        plaintext.build = LocalWireBuild.current
        plaintext.contract = ContractVersion.contract
        plaintext.minReadable = ContractVersion.minReadable
        let assignment = sessionManager.offscreenAssignment(now: now)
        plaintext.notifyOn = assignment.on
        plaintext.notifyTurn = assignment.turn
        plaintext.notifyFireAt = assignment.fireAt
        return plaintext
    }
}
