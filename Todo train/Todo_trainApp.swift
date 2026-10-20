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
    @State private var companion = CompanionSyncRuntime()

    init() {
        do {
            #if DEBUG
            let usePreviewStore = FocusUIPreview.isActive
            #else
            let usePreviewStore = false
            #endif
            let container = try AppModelContainer.make(inMemory: usePreviewStore)
            self.container = container
            let context = container.mainContext
            #if DEBUG
            let uiPreviewLaunch = FocusUIPreview.isActive
            #else
            let uiPreviewLaunch = false
            #endif
            #if canImport(ActivityKit)
            #if DEBUG
            let suppressLiveActivity = uiPreviewLaunch && !FocusUIPreview.wantsLiveActivity
            #else
            let suppressLiveActivity = false
            #endif
            let liveActivity: any LiveActivityManaging = suppressLiveActivity
                ? NoOpLiveActivityManager()
                : LiveActivityManager.shared
            #else
            let liveActivity: any LiveActivityManaging = NoOpLiveActivityManager()
            #endif
            #if canImport(AlarmKit)
            let alarmScheduler: any AlarmScheduling = uiPreviewLaunch
                ? NoOpAlarmScheduler()
                : AlarmKitScheduler.shared
            #else
            let alarmScheduler: any AlarmScheduling = NoOpAlarmScheduler()
            #endif
            #if DEBUG
            let overtimeNotifier: any OvertimeNotifying = uiPreviewLaunch
                ? NoOpOvertimeNotifier()
                : OvertimeNotifier.shared
            let checkInNotifier: any CheckInNotifying = uiPreviewLaunch
                ? NoOpCheckInNotifier()
                : CheckInNotifier.shared
            #else
            let overtimeNotifier: any OvertimeNotifying = OvertimeNotifier.shared
            let checkInNotifier: any CheckInNotifying = CheckInNotifier.shared
            #endif
            #if DEBUG
            let calendarBoard: (any CalendarBoard)? = uiPreviewLaunch ? InMemoryCalendarBoard() : nil
            #else
            let calendarBoard: (any CalendarBoard)? = nil
            #endif
            let manager = SessionManager(
                modelContext: context,
                settings: AppSettings.shared,
                overtimeNotifier: overtimeNotifier,
                checkInNotifier: checkInNotifier,
                coachingEngine: CoachingEngineFactory.make(),
                liveActivityManager: liveActivity,
                alarmScheduler: alarmScheduler,
                calendarBoard: calendarBoard
            )
            _sessionManager = State(initialValue: manager)
            AppRuntime.modelContainer = container
            AppRuntime.sessionManager = manager
            if !uiPreviewLaunch {
                WatchSessionBridge.shared.activate()
            }
            #if canImport(AlarmKit)
            if !uiPreviewLaunch {
                AlarmKitScheduler.shared.bind(sessionManager: manager)
            }
            #endif
            if !uiPreviewLaunch {
                OvertimeNotifier.shared.sessionManager = manager
                OvertimeNotifier.shared.configure()
                CheckInNotifier.shared.configure()
            }
            SessionPauseRuntime.pauser = manager
            RideControlRuntime.installed = manager
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-SeedHistoryTimeline") {
                let existing = (try? context.fetch(FetchDescriptor<WorkSession>())) ?? []
                if !existing.contains(where: { $0.endedAt != nil }) {
                    HistoryPreviewSeed.insertSampleWeek(into: context)
                }
            }
            if FocusUIPreview.isActive {
                try FocusUIPreview.bootstrap(manager: manager, context: context)
            }
            #endif
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
                .environment(companion)
                .environment(ArrivalForecastTraceLog.shared)
                .environment(ArrivalForecastStore.shared)
                .modelContainer(container)
        }
    }
}
