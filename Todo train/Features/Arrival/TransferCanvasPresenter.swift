//
//  TransferCanvasPresenter.swift
//  Todo train
//
//  Hosts 乗り継ぎ canvas above Focus. Partial disembark ends the session and
//  dismisses Focus; presenting the canvas from Focus itself races that dismiss.
//

import Foundation
import Observation

@Observable
@MainActor
final class TransferCanvasPresenter {
    struct Launch: Identifiable {
        let id = UUID()
        let parent: Ticket
        let sessionID: UUID?
    }

    /// Waiting for Focus fullScreenCover to finish dismissing.
    private(set) var pending: Launch?
    /// Sheet currently shown from ContentView.
    var active: Launch?

    /// Queue while Focus is tearing down; ContentView promotes on dismiss.
    func enqueueAfterFocusDismiss(parent: Ticket, sessionID: UUID?) {
        pending = Launch(parent: parent, sessionID: sessionID)
    }

    func clearPending() {
        pending = nil
    }

    func presentPendingIfNeeded() {
        guard active == nil, let pending else { return }
        active = pending
        self.pending = nil
    }
}
