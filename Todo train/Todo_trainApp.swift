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
            _sessionManager = State(
                initialValue: SessionManager(
                    modelContext: context,
                    settings: AppSettings.shared,
                    overtimeNotifier: OvertimeNotifier.shared,
                    liveActivityManager: liveActivity,
                    alarmScheduler: alarmScheduler
                )
            )
            OvertimeNotifier.shared.configure()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(settings)
                .modelContainer(container)
        }
    }
}
