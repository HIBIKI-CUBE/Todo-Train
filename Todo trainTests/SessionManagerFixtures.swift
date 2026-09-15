//
//  SessionManagerFixtures.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
enum SessionManagerFixtures {
    static func makeHarness(
        now: Date = Date(timeIntervalSince1970: 1_700_000_000),
        pauseLimit: Int = PauseLimitGuard.defaultLimit,
        endBellEnabled: Bool = false,
        cabinAnnouncementsEnabled: Bool = true,
        alarmScheduler: InMemoryAlarmScheduler? = nil,
        checkInNotifier: (any CheckInNotifying)? = nil,
        liveActivityManager: (any LiveActivityManaging)? = nil,
        deviceIdentity: (any DeviceIdentifying)? = nil,
        deviceLock: (any DeviceLockReading)? = nil,
        calendarBoard: (any CalendarBoard)? = nil
    ) throws -> (SessionManager, ModelContext, FixedSessionClock, InMemoryAlarmScheduler) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let clock = FixedSessionClock(now)
        let settings = AppSettings.makeForTesting(
            pauseLimit: pauseLimit,
            endBellEnabled: endBellEnabled,
            cabinAnnouncementsEnabled: cabinAnnouncementsEnabled
        )
        let scheduler = alarmScheduler ?? InMemoryAlarmScheduler()
        let manager = SessionManager(
            modelContext: context,
            clock: clock,
            settings: settings,
            checkInNotifier: checkInNotifier ?? NoOpCheckInNotifier(),
            liveActivityManager: liveActivityManager,
            alarmScheduler: scheduler,
            deviceIdentity: deviceIdentity ?? FixedDeviceIdentity(id: "test-device"),
            deviceLock: deviceLock ?? FixedDeviceLock(isLocked: false),
            calendarBoard: calendarBoard ?? InMemoryCalendarBoard()
        )
        return (manager, context, clock, scheduler)
    }

    static func makeTicket(
        _ context: ModelContext,
        title: String = "A",
        seconds: Int = 1800
    ) throws -> Ticket {
        let ticket = Ticket(title: title, estimatedSeconds: seconds)
        context.insert(ticket)
        try context.save()
        return ticket
    }
}
