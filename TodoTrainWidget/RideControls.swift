//
//  RideControls.swift
//  Shared by the app and TodoTrainWidget.
//
//  発車・続行・停車・再乗車・到着。到着はコントロールであり、ダブルタップの主操作ではない。
//  前面には出さない。実行先は iPhone のアプリで、画面のボタンと同じ処理を呼ぶ。
//

import AppIntents
import SwiftUI
import WidgetKit

struct RideControlEffect: Equatable, Sendable {
    var dialog: String
}

@MainActor
protocol RideControlPerforming: AnyObject {
    func boardReservedFromControl() -> RideControlEffect
    func continueFromControl() -> RideControlEffect
    func pauseFromControl() -> RideControlEffect
    func resumeFromControl() -> RideControlEffect
    func arriveFromControl() -> RideControlEffect
}

@MainActor
enum RideControlRuntime {
    static var installed: (any RideControlPerforming)?
    static var testing: [UUID: any RideControlPerforming] = [:]

    static func current() -> (any RideControlPerforming)? {
        if let id = RideControlCall.testingID, let performer = testing[id] {
            return performer
        }
        return installed
    }
}

nonisolated enum RideControlCall {
    @TaskLocal static var testingID: UUID?
}

nonisolated enum RideControlIntentStyle {
    static let unread = "走行の状態を読んでいません。"
}

struct BoardReservedRideIntent: AppIntent {
    static var title: LocalizedStringResource = "予約の切符で発車"
    static var description = IntentDescription("予約してある切符で発車します。")
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await MainActor.run {
            RideControlRuntime.current()?.boardReservedFromControl().dialog ?? RideControlIntentStyle.unread
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

struct ContinueRideIntent: AppIntent {
    static var title: LocalizedStringResource = "続行"
    static var description = IntentDescription("走行中の問いを続行にします。")
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await MainActor.run {
            RideControlRuntime.current()?.continueFromControl().dialog ?? RideControlIntentStyle.unread
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

struct PauseRideIntent: AppIntent {
    static var title: LocalizedStringResource = "停車"
    static var description = IntentDescription("走行中の切符を停車します。")
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await MainActor.run {
            RideControlRuntime.current()?.pauseFromControl().dialog ?? RideControlIntentStyle.unread
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

struct ResumeRideIntent: AppIntent {
    static var title: LocalizedStringResource = "再乗車"
    static var description = IntentDescription("停車中の切符を再乗車します。")
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await MainActor.run {
            RideControlRuntime.current()?.resumeFromControl().dialog ?? RideControlIntentStyle.unread
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

struct ArriveRideIntent: AppIntent {
    static var title: LocalizedStringResource = "到着"
    static var description = IntentDescription("走行中の切符を到着にします。")
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { .background }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog = await MainActor.run {
            RideControlRuntime.current()?.arriveFromControl().dialog ?? RideControlIntentStyle.unread
        }
        return .result(dialog: IntentDialog(LocalizedStringResource(stringLiteral: dialog)))
    }
}

struct BoardReservedRideControl: ControlWidget {
    static let kind = "dev.hibiki-cube.Todo-train.control.boardReserved"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: BoardReservedRideIntent()) {
                Label("予約の切符で発車", systemImage: "tram.fill")
            }
        }
        .displayName("予約の切符で発車")
        .description("予約してある切符で発車します。")
    }
}

struct ContinueRideControl: ControlWidget {
    static let kind = "dev.hibiki-cube.Todo-train.control.continue"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ContinueRideIntent()) {
                Label("続行", systemImage: "arrow.forward")
            }
        }
        .displayName("続行")
        .description("走行中の問いを続行にします。")
    }
}

struct PauseRideControl: ControlWidget {
    static let kind = "dev.hibiki-cube.Todo-train.control.pause"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: PauseRideIntent()) {
                Label("停車", systemImage: "pause.fill")
            }
        }
        .displayName("停車")
        .description("走行中の切符を停車します。")
    }
}

struct ResumeRideControl: ControlWidget {
    static let kind = "dev.hibiki-cube.Todo-train.control.resume"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ResumeRideIntent()) {
                Label("再乗車", systemImage: "play.fill")
            }
        }
        .displayName("再乗車")
        .description("停車中の切符を再乗車します。")
    }
}

struct ArriveRideControl: ControlWidget {
    static let kind = "dev.hibiki-cube.Todo-train.control.arrive"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: ArriveRideIntent()) {
                Label("到着", systemImage: "flag.checkered")
            }
        }
        .displayName("到着")
        .description("走行中の切符を到着にします。")
    }
}
