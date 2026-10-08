//
//  ArrivalPresentCrashTests.swift
//  Todo trainTests
//
//  到着で Focus を閉じ、祝祭と発車層を同じ更新で出す。
//

import SwiftData
import SwiftUI
import UIKit
import Testing
@testable import Todo_train

@MainActor
struct ArrivalPresentCrashTests {
    @Test func arriveWithReservation_presentsOverlayWithoutTrap() throws {
        let host = try ArrivalCrashWindow.make(reserve: true)
        host.install()
        host.pump(times: 8)
        try host.manager.arrive()
        host.pump(times: 12)
        #expect(host.manager.phase != .running)
        #expect(host.manager.punctualityMoment != nil)
    }
}

@MainActor
private final class ArrivalCrashWindow {
    let manager: SessionManager
    let settings: AppSettings
    let container: ModelContainer
    private var window: UIWindow?

    private init(manager: SessionManager, settings: AppSettings, container: ModelContainer) {
        self.manager = manager
        self.settings = settings
        self.container = container
    }

    static func make(reserve: Bool) throws -> ArrivalCrashWindow {
        let (manager, context, _, _) = try SessionManagerFixtures.makeHarness()
        let settings = AppSettings.makeForTesting()
        let riding = try SessionManagerFixtures.makeTicket(context, title: "今の切符", seconds: 600)
        try manager.startService()
        try manager.board(ticket: riding)
        if reserve {
            let next = try SessionManagerFixtures.makeTicket(context, title: "次の切符", seconds: 900)
            try manager.reserveNextRide(ticket: next, via: .riding)
        }
        return ArrivalCrashWindow(manager: manager, settings: settings, container: context.container)
    }

    func install() {
        let root = ArrivalCrashHost(manager: manager, settings: settings, container: container)
            .environment(manager)
            .environment(settings)
            .environment(DeletionUndoCenter())
            .environment(ArrivalForecastTraceLog.shared)
            .environment(ArrivalForecastStore.shared)
            .modelContainer(container)
        let controller = UIHostingController(rootView: root)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }

    func pump(times: Int) {
        for _ in 0..<times {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }
}

private struct ArrivalCrashHost: View {
    let manager: SessionManager
    let settings: AppSettings
    let container: ModelContainer

    @State private var ticketMotion = TicketMotionBridge()
    @State private var isFocusPresented = false
    @Namespace private var focusZoom

    var body: some View {
        HubView()
            .environment(manager)
            .environment(settings)
            .environment(DeletionUndoCenter())
            .environment(ticketMotion)
            .environment(ArrivalForecastTraceLog.shared)
            .environment(ArrivalForecastStore.shared)
            .environment(\.focusZoomNamespace, focusZoom)
            .environment(\.isFocusCoverPresented, isFocusPresented)
            .modelContainer(container)
            .fullScreenCover(isPresented: $isFocusPresented) {
                FocusView()
                    .environment(manager)
                    .environment(settings)
                    .environment(ticketMotion)
                    .environment(ArrivalForecastTraceLog.shared)
                    .environment(ArrivalForecastStore.shared)
                    .modelContainer(container)
                    .interactiveDismissDisabled()
                    .navigationTransition(
                        .zoom(
                            sourceID: ticketMotion.zoomSourceID
                                ?? manager.activeSession?.ticket?.id
                                ?? TicketMotionBridge.missingSource,
                            in: focusZoom
                        )
                    )
            }
            .onAppear(perform: syncFocus)
            .onChange(of: manager.phase) { _, _ in
                syncFocus()
            }
            .overlay {
                if let moment = manager.punctualityMoment, case .arrival = moment.kind {
                    ArrivalInvalidateOverlay(
                        moment: moment,
                        skipEnter: true,
                        onClose: { manager.consumePunctualityMoment() },
                        onStamp: { sessionID, action in
                            try manager.recordArrivalStamp(sessionID: sessionID, action: action)
                        },
                        onLeadingBoard: { ticketID in
                            try manager.boardFromArrivalSwipe(ticketID: ticketID)
                        }
                    )
                    .environment(ticketMotion)
                    .id(moment.id)
                }
            }
    }

    private func syncFocus() {
        let should = manager.shouldPresentFocusCover && !ticketMotion.suppressFocusCover
        if isFocusPresented != should {
            isFocusPresented = should
        }
    }
}
