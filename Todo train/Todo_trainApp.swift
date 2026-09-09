//
//  Todo_trainApp.swift
//  Todo train
//

import SwiftUI
import SwiftData

@main
struct Todo_trainApp: App {
    private let container: ModelContainer
    @State private var sessionManager: SessionManager
    @State private var settings = AppSettings.shared
    @State private var deletionUndo = DeletionUndoCenter()

    init() {
        do {
            let container = try AppModelContainer.make(inMemory: false)
            self.container = container
            let context = container.mainContext
            #if canImport(ActivityKit)
            let liveActivity: any LiveActivityManaging = LiveActivityManager.shared
            #else
            let liveActivity: any LiveActivityManaging = NoOpLiveActivityManager()
            #endif
            #if canImport(AlarmKit)
            let alarmScheduler: any AlarmScheduling = AlarmKitScheduler.shared
            #else
            let alarmScheduler: any AlarmScheduling = NoOpAlarmScheduler()
            #endif
            let manager = SessionManager(
                modelContext: context,
                settings: AppSettings.shared,
                overtimeNotifier: OvertimeNotifier.shared,
                checkInNotifier: CheckInNotifier.shared,
                coachingEngine: CoachingEngineFactory.make(),
                liveActivityManager: liveActivity,
                alarmScheduler: alarmScheduler
            )
            _sessionManager = State(initialValue: manager)
            AppRuntime.modelContainer = container
            AppRuntime.sessionManager = manager
            #if canImport(AlarmKit)
            AlarmKitScheduler.shared.bind(sessionManager: manager)
            #endif
            OvertimeNotifier.shared.sessionManager = manager
            OvertimeNotifier.shared.configure()
            CheckInNotifier.shared.configure()
            SessionPauseRuntime.pauser = manager
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(settings)
                .environment(deletionUndo)
                .modelContainer(container)
        }
    }
}
