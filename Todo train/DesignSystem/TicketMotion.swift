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
    /// Zoom is always applied on iOS 27; this is only a last-resort id.
    static let missingSource = UUID()
}

extension EnvironmentValues {
    @Entry var focusZoomNamespace: Namespace.ID? = nil
    @Entry var isFocusCoverPresented: Bool = false
}

struct TicketSlotFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

