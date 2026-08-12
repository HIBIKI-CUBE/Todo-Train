//
//  EndBellIntents.swift
//  Shared by app + TodoTrainWidget.
//
//  Live Activity buttons must use LiveActivityIntent — AlarmPresentation
//  pause/resume only applies to the system templated fallback UI.
//

import AppIntents
import Foundation

#if canImport(AlarmKit)
import AlarmKit

struct EndBellPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "停車"
    static var description = IntentDescription("終了ベルのカウントダウンを停車します。")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { alarmID = "" }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.pause(id: id)
        return .result()
    }
}

struct EndBellResumeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "再乗車"
    static var description = IntentDescription("停車中の終了ベルを再開します。")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { alarmID = "" }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.resume(id: id)
        return .result()
    }
}

/// Cancels the countdown (Clock-style dismiss) without marking the ticket arrived.
struct EndBellCancelIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "キャンセル"
    static var description = IntentDescription("終了ベルのカウントダウンを取り消します。")

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() { alarmID = "" }

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarmID) else { return .result() }
        try AlarmManager.shared.cancel(id: id)
        return .result()
    }
}

struct EndBellStopIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "終了ベルを停止"
    static var description = IntentDescription("見積もり終了ベルを止めます。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Alarm ID")
    var alarmID: String

    @Parameter(title: "Session ID")
    var sessionID: String

    init() {
        alarmID = ""
        sessionID = ""
    }

    init(alarmID: UUID, sessionID: UUID) {
        self.alarmID = alarmID.uuidString
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        // System already stopped the alert when this runs from AlarmConfiguration.stopIntent.
        .result()
    }
}

/// Opens the app so the user can arrive from Focus (overtime keeps the 3-choice UI).
struct EndBellArriveIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "到着"
    static var description = IntentDescription("アプリを開いて到着します。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { return .result() }
        FocusPendingActionStore.enqueue(
            FocusPendingAction(kind: .arrive, sessionID: id, createdAt: .now)
        )
        return .result()
    }
}

/// Opens Focus with the extend panel (inline extend would desync Alarm vs DB).
struct EndBellExtendIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "延長"
    static var description = IntentDescription("アプリを開いて延長します。")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Session ID")
    var sessionID: String

    init() { sessionID = "" }

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: sessionID) else { return .result() }
        FocusPendingActionStore.enqueue(
            FocusPendingAction(kind: .extend, sessionID: id, createdAt: .now)
        )
        return .result()
    }
}
#endif
