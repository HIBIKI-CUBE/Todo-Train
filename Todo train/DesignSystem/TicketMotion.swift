//
//  TicketMotion.swift
//  Todo train
//
//  iOS 27 motion plumbing. Zoom namespace is required in the app
//  (ContentView). Overlay is the traveling identity, not a fade-clone.
//

import SwiftUI

@Observable
final class TicketMotionBridge {
    /// Source id for `navigationTransition(.zoom)` on Focus cover.
    var zoomSourceID: UUID?
    /// Hide Focus without reverse-zoom so an interrupt ticket can be the next source.
    var suppressFocusCover = false
    /// Issued ticket playing on Hub/Content while Focus is suppressed.
    var interruptEject: TicketIssueEjectEvent?
    /// Zoom is always applied on iOS 27; this is only a last-resort id.
    static let missingSource = UUID()

    func presentInterruptTicket(_ event: TicketIssueEjectEvent) {
        zoomSourceID = event.ticketID
        interruptEject = event
        suppressFocusCover = true
    }

    func commitInterruptZoom() {
        suppressFocusCover = false
    }

    func cancelInterruptTicket() {
        interruptEject = nil
        suppressFocusCover = false
    }
}

extension EnvironmentValues {
    @Entry var focusZoomNamespace: Namespace.ID? = nil
    @Entry var isFocusCoverPresented: Bool = false
}

struct TicketDeckFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isNull {
            value = next
        }
    }
}

/// Latest deck slots. Class mutation does not invalidate Hub during scroll.
final class HubSlotFrameCache {
    var frames: [UUID: CGRect] = [:]
}

