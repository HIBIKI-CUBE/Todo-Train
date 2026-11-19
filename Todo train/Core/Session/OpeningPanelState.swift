//
//  OpeningPanelState.swift
//  Todo train
//
//  運行開始の盤の状態機械。描画と音声の実体は持たない。
//  時間は注入したスケジューラだけが進める。
//

import Foundation
import Observation

/// 仕様「間」の既定。テンポが付いた値は 100/170 を掛けた長さ。
enum OpeningPanelTiming {
    static let tempoPercent: Double = 170

    static func tempo(_ milliseconds: Double) -> TimeInterval {
        milliseconds * 100 / tempoPercent / 1_000
    }

    static let lampCheck: TimeInterval = 0.280
    static let autoWait: TimeInterval = 0.800
    static let autoGap: TimeInterval = 0.120
    static let backlight: TimeInterval = 0.050

    static let ledCount = 6
    /// 70ms × 0.6（テンポ）。
    static var powerLEDStep: TimeInterval { tempo(70 * 0.6) }
    static var powerLEDSettle: TimeInterval { tempo(150) }

    static let clockDigitGlyphs = ["8", "88", "888", "8888"]
    static var clockDigit: TimeInterval { tempo(110) }
    /// `8888` を 1 段見せたあと、消灯してから実時刻までの長さ。
    static var clockToLive: TimeInterval { tempo(300) }

    static let timetableFillCount = 12
    static var timetableFill: TimeInterval { tempo(32) }
    static var timetableToInTest: TimeInterval { tempo(150) }
    /// 描画までの 300ms にはテンポを掛けない。
    static let timetableDraw: TimeInterval = 0.300

    static var ticketCursor: TimeInterval { tempo(70) }
    static var ticketAfterCursor: TimeInterval { tempo(150) }
    /// 切符 1 枚の間隔にはテンポを掛けない。
    static let ticketStep: TimeInterval = 0.110

    static var checkBlink: TimeInterval { tempo(60) }
    /// 点・滅・点・滅・点。最後の段番号。
    static let checkBlinkLast = 4

    static let departBarStep: TimeInterval = 0.022
    static let departBarSteps = 3
    static let departLockStagger: TimeInterval = 0.028
    static let departSweepLead: TimeInterval = 0.150
    static let departModuleStagger: TimeInterval = 0.022
    static let departModuleGlow: TimeInterval = 0.060
    /// Hub へ切り替える式の末尾。走査の開始と同じ 150ms だが、別の項。
    static let hubTail: TimeInterval = 0.150
    static let departColumnFlash: TimeInterval = 0.120
    /// 矢羽根 1 本ごとの間。仕様は順番だけなので、参照モックの並び。
    static let chevronLead: TimeInterval = 0.090
    static let chevronSteps: [TimeInterval] = [
        0.050, 0.040, 0.032, 0.026, 0.022, 0.019, 0.017, 0.015, 0.014, 0.014,
    ]

    /// 盤のモジュール数。sysbar（CHK・PHONE）は一つ。
    static var moduleCount: Int { OpeningPanelFace.allCases.count }
    static var hubSwitch: TimeInterval {
        tempo(260) + Double(moduleCount) * departModuleStagger + hubTail
    }
}

/// 上から下。DEPART の縁の走査は逆順。
enum OpeningPanelFace: CaseIterable, Hashable {
    case sysbar
    case master
    case clock
    case clockKey
    case timetable
    case nowBoard
    case tickets
    case load
    case comm
    case depart
}

enum OpeningPanelModuleID: CaseIterable, Hashable {
    case clock
    case timetable
    case tickets

    static let bootOrder: [OpeningPanelModuleID] = [.clock, .timetable, .tickets]

    var meter: OpeningPanelMeter {
        switch self {
        case .clock: .clock
        case .timetable: .timetable
        case .tickets: .tickets
        }
    }
}

enum OpeningPanelMeter: CaseIterable, Hashable {
    case master
    case clock
    case timetable
    case tickets
}

enum OpeningPanelConfirmation: Equatable {
    case unconfirmed
    case confirming
    case confirmed
}

enum OpeningPanelClockStage: Equatable {
    case dark
    case backlight
    case digits(String)
    case blank
    case live

    /// 桁の段番号。`8` が 1、`8888` が 4、消灯が 5、実時刻が 6。
    var stageNumber: Int {
        switch self {
        case .dark, .backlight:
            return 0
        case .digits(let glyphs):
            return glyphs.count
        case .blank:
            return 5
        case .live:
            return 6
        }
    }
}

enum OpeningPanelTimetableStage: Equatable {
    case dark
    case backlight
    case fill(Int)
    case inTest
    case drawn

    /// 充填は 1…12。IN TEST は 13、描画後は 14。
    var stageNumber: Int {
        switch self {
        case .dark, .backlight:
            return 0
        case .fill(let step):
            return step
        case .inTest:
            return OpeningPanelTiming.timetableFillCount + 1
        case .drawn:
            return OpeningPanelTiming.timetableFillCount + 2
        }
    }
}

enum OpeningPanelTicketsStage: Equatable {
    case dark
    case backlight
    case cursor(Int)
    case shown(Int)

    /// カーソルの行数、または見えている切符の枚数。
    var stageNumber: Int {
        switch self {
        case .dark, .backlight:
            return 0
        case .cursor(let rows), .shown(let rows):
            return rows
        }
    }
}

enum OpeningPanelLampCheck: Equatable {
    case off
    case allOn
    case done
}

enum OpeningPanelCue: Equatable {
    case light
    case heavy
    case dull
    case haptic(OpeningPanelHaptic)
}

enum OpeningPanelHaptic: Equatable {
    /// 10ms。押したとき。
    case operation
    /// 8ms。TODAY の区切りを移したとき。盤の状態機械は区切りを動かさない。
    case divider
    /// 30ms。DEPART。
    case depart
}

protocol OpeningPanelFeedback: AnyObject {
    func play(_ cue: OpeningPanelCue)
}

struct OpeningPanelTask {
    private let cancelAction: () -> Void

    init(_ cancelAction: @escaping () -> Void = {}) {
        self.cancelAction = cancelAction
    }

    func cancel() {
        cancelAction()
    }
}

protocol OpeningPanelScheduling: AnyObject {
    @discardableResult
    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask
}

/// 画面に出すまでの待ち。テストは `OpeningPanelScheduling` を差し替える。
final class OpeningPanelDispatchScheduler: OpeningPanelScheduling {
    func schedule(after seconds: TimeInterval, execute: @escaping () -> Void) -> OpeningPanelTask {
        let nanos = UInt64(max(0, (seconds * 1_000_000_000).rounded()))
        let task = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: nanos)
            } catch {
                return
            }
            execute()
        }
        return OpeningPanelTask { task.cancel() }
    }
}

/// MASTER・CLOCK・TT・TKT・DEPART の盤。切符の並びと TODAY の区切りは持たない。
@Observable
final class OpeningPanelState {
    private let scheduler: any OpeningPanelScheduling
    private let feedback: any OpeningPanelFeedback
    private let onStartService: () -> Void
    private let onCommitSequence: () -> Void
    private let onShowHub: () -> Void

    let reducesMotion: Bool
    var ticketCount: Int

    private(set) var isPowered = false
    /// 一度でも MASTER を入れたら真。切っても偽に戻さない。
    private(set) var serviceStarted = false
    private(set) var isReady = false
    private(set) var isSequencing = false
    private(set) var hasDeparted = false

    private(set) var lampCheck: OpeningPanelLampCheck = .off
    private(set) var powerLEDCount = 0
    private(set) var powerSettled = false
    private(set) var clockStage: OpeningPanelClockStage = .dark
    private(set) var timetableStage: OpeningPanelTimetableStage = .dark
    private(set) var ticketsStage: OpeningPanelTicketsStage = .dark

    private(set) var departBarDepth = 0
    private(set) var departColumnLit = false
    private(set) var chevronFill = 0
    private(set) var glowingFaces: Set<OpeningPanelFace> = []

    private var confirmation: [OpeningPanelModuleID: OpeningPanelConfirmation] = [:]
    private var generations: [OpeningPanelModuleID: Int] = [:]
    private var powerGeneration = 0
    private var checkSteps: [OpeningPanelMeter: Int] = [:]
    private var locks: Set<OpeningPanelMeter> = []

    private var moduleTasks: [OpeningPanelModuleID: [OpeningPanelTask]] = [:]
    private var powerTasks: [OpeningPanelTask] = []
    private var autoTasks: [OpeningPanelTask] = []
    private var departTasks: [OpeningPanelTask] = []

    init(
        scheduler: any OpeningPanelScheduling,
        feedback: any OpeningPanelFeedback,
        ticketCount: Int = 0,
        reduceMotion: Bool = false,
        onStartService: @escaping () -> Void = {},
        onCommitSequence: @escaping () -> Void = {},
        onShowHub: @escaping () -> Void = {}
    ) {
        self.scheduler = scheduler
        self.feedback = feedback
        self.ticketCount = max(0, ticketCount)
        self.reducesMotion = reduceMotion
        self.onStartService = onStartService
        self.onCommitSequence = onCommitSequence
        self.onShowHub = onShowHub
    }

    func confirmation(of module: OpeningPanelModuleID) -> OpeningPanelConfirmation {
        confirmation[module, default: .unconfirmed]
    }

    func generation(of module: OpeningPanelModuleID) -> Int {
        generations[module, default: 0]
    }

    /// まだ手で入れていない確認。縁の示唆に使う。MASTER は入らない。
    var nextAutomaticModule: OpeningPanelModuleID? {
        guard isPowered, !hasDeparted else { return nil }
        return OpeningPanelModuleID.bootOrder.first { confirmation(of: $0) == .unconfirmed }
    }

    var readyLampLit: Bool {
        isReady && !hasDeparted
    }

    /// READY のあいだ、矢羽根が押し棒へ流れる。
    var chevronsFlowing: Bool {
        isReady && !hasDeparted && !reducesMotion
    }

    /// 視差効果を減らすときは流さず、薄く点けたままにする。
    var chevronsHeldDim: Bool {
        reducesMotion && (isReady || hasDeparted)
    }

    func checkStep(for meter: OpeningPanelMeter) -> Int? {
        checkSteps[meter]
    }

    /// 段 0, 2, 4 が点。
    func checkIsLit(_ meter: OpeningPanelMeter) -> Bool {
        guard let step = checkSteps[meter] else { return false }
        return step.isMultiple(of: 2)
    }

    func isLockLit(_ meter: OpeningPanelMeter) -> Bool {
        locks.contains(meter)
    }

    func pressMaster() {
        guard !hasDeparted else { return }
        if isPowered {
            powerOff()
            return
        }
        isPowered = true
        serviceStarted = true
        onStartService()
        feedback.play(.light)
        feedback.play(.haptic(.operation))
        beginPower()
        rearmAuto()
    }

    func pressConfirm(_ module: OpeningPanelModuleID) {
        guard !hasDeparted else { return }
        guard isPowered else {
            feedback.play(.dull)
            return
        }
        feedback.play(.light)
        feedback.play(.haptic(.operation))
        begin(module)
        rearmAuto()
    }

    func pressSequence() {
        guard !hasDeparted else { return }
        guard isPowered, confirmation(of: .tickets) == .confirmed else {
            feedback.play(.dull)
            return
        }
        if isSequencing {
            commitSequence()
        } else {
            isSequencing = true
        }
        feedback.play(.light)
        feedback.play(.haptic(.operation))
        rearmAuto()
    }

    func pressDepart() {
        guard !hasDeparted else { return }
        guard isPowered else {
            feedback.play(.dull)
            return
        }
        if isSequencing {
            commitSequence()
        }
        feedback.play(.heavy)
        feedback.play(.haptic(.depart))
        beginDepart()
    }

    private func commitSequence() {
        guard isSequencing else { return }
        isSequencing = false
        onCommitSequence()
    }

    private func powerOff() {
        feedback.play(.light)
        feedback.play(.haptic(.operation))
        cancelAuto()
        cancelDepart()
        invalidatePower()
        for module in OpeningPanelModuleID.allCases {
            _ = bump(module)
        }
        isPowered = false
        isReady = false
        isSequencing = false
        lampCheck = .off
        powerLEDCount = 0
        powerSettled = false
        clockStage = .dark
        timetableStage = .dark
        ticketsStage = .dark
        confirmation.removeAll()
        checkSteps.removeAll()
        locks.removeAll()
        glowingFaces.removeAll()
        departBarDepth = 0
        departColumnLit = false
        chevronFill = 0
    }

    private func beginPower() {
        let generation = invalidatePower()
        if reducesMotion {
            lampCheck = .done
            showLED(1, generation: generation)
            return
        }
        lampCheck = .allOn
        powerLEDCount = OpeningPanelTiming.ledCount
        afterPower(OpeningPanelTiming.lampCheck, generation: generation) { state in
            state.lampCheck = .done
            state.showLED(1, generation: generation)
        }
    }

    private func showLED(_ count: Int, generation: Int) {
        guard powerGeneration == generation else { return }
        powerLEDCount = count
        if count < OpeningPanelTiming.ledCount {
            afterPower(OpeningPanelTiming.powerLEDStep, generation: generation) { state in
                state.showLED(count + 1, generation: generation)
            }
        } else {
            afterPower(OpeningPanelTiming.powerLEDSettle, generation: generation) { state in
                state.settlePower(generation: generation)
            }
        }
    }

    private func settlePower(generation: Int) {
        guard powerGeneration == generation, isPowered, !hasDeparted else { return }
        powerSettled = true
        locks.insert(.master)
        showCheck(.master, step: 0, generation: generation, module: nil)
    }

    private func begin(_ module: OpeningPanelModuleID) {
        guard isPowered, !hasDeparted else { return }
        let generation = bump(module)
        confirmation[module] = .confirming
        isReady = false
        locks.remove(module.meter)
        checkSteps.removeValue(forKey: module.meter)
        switch module {
        case .clock:
            beginClock(generation)
        case .timetable:
            beginTimetable(generation)
        case .tickets:
            beginTickets(generation)
        }
    }

    private func beginClock(_ generation: Int) {
        clockStage = .backlight
        after(OpeningPanelTiming.backlight, module: .clock, generation: generation) { state in
            if state.reducesMotion {
                state.finishClock(generation: generation)
            } else {
                state.showClockDigit(0, generation: generation)
            }
        }
    }

    private func showClockDigit(_ index: Int, generation: Int) {
        guard self.generation(of: .clock) == generation else { return }
        let glyphs = OpeningPanelTiming.clockDigitGlyphs
        guard index < glyphs.count else { return }
        clockStage = .digits(glyphs[index])
        after(OpeningPanelTiming.clockDigit, module: .clock, generation: generation) { state in
            if index + 1 < glyphs.count {
                state.showClockDigit(index + 1, generation: generation)
            } else {
                state.blankClock(generation: generation)
            }
        }
    }

    private func blankClock(generation: Int) {
        guard self.generation(of: .clock) == generation else { return }
        clockStage = .blank
        after(OpeningPanelTiming.clockToLive, module: .clock, generation: generation) { state in
            state.finishClock(generation: generation)
        }
    }

    private func finishClock(generation: Int) {
        guard self.generation(of: .clock) == generation else { return }
        clockStage = .live
        feedback.play(.light)
        noteConfirmed(.clock)
    }

    private func beginTimetable(_ generation: Int) {
        timetableStage = .backlight
        after(OpeningPanelTiming.backlight, module: .timetable, generation: generation) { state in
            if state.reducesMotion {
                state.finishTimetable(generation: generation)
            } else {
                state.showFill(1, generation: generation)
            }
        }
    }

    private func showFill(_ step: Int, generation: Int) {
        guard self.generation(of: .timetable) == generation else { return }
        timetableStage = .fill(step)
        if step < OpeningPanelTiming.timetableFillCount {
            after(OpeningPanelTiming.timetableFill, module: .timetable, generation: generation) { state in
                state.showFill(step + 1, generation: generation)
            }
        } else {
            after(OpeningPanelTiming.timetableToInTest, module: .timetable, generation: generation) { state in
                state.showInTest(generation: generation)
            }
        }
    }

    private func showInTest(generation: Int) {
        guard self.generation(of: .timetable) == generation else { return }
        timetableStage = .inTest
        after(OpeningPanelTiming.timetableDraw, module: .timetable, generation: generation) { state in
            state.finishTimetable(generation: generation)
        }
    }

    private func finishTimetable(generation: Int) {
        guard self.generation(of: .timetable) == generation else { return }
        timetableStage = .drawn
        feedback.play(.light)
        noteConfirmed(.timetable)
    }

    private func beginTickets(_ generation: Int) {
        ticketsStage = .backlight
        let count = max(0, ticketCount)
        after(OpeningPanelTiming.backlight, module: .tickets, generation: generation) { state in
            if state.reducesMotion || count == 0 {
                state.finishTickets(shown: count, generation: generation)
            } else {
                state.showCursor(1, count: count, generation: generation)
            }
        }
    }

    private func showCursor(_ rows: Int, count: Int, generation: Int) {
        guard self.generation(of: .tickets) == generation else { return }
        ticketsStage = .cursor(rows)
        if rows < count {
            after(OpeningPanelTiming.ticketCursor, module: .tickets, generation: generation) { state in
                state.showCursor(rows + 1, count: count, generation: generation)
            }
        } else {
            after(OpeningPanelTiming.ticketAfterCursor, module: .tickets, generation: generation) { state in
                state.revealTicket(1, count: count, generation: generation)
            }
        }
    }

    private func revealTicket(_ shown: Int, count: Int, generation: Int) {
        guard self.generation(of: .tickets) == generation else { return }
        ticketsStage = .shown(shown)
        feedback.play(.light)
        feedback.play(.haptic(.operation))
        if shown < count {
            after(OpeningPanelTiming.ticketStep, module: .tickets, generation: generation) { state in
                state.revealTicket(shown + 1, count: count, generation: generation)
            }
        } else {
            noteConfirmed(.tickets)
        }
    }

    private func finishTickets(shown: Int, generation: Int) {
        guard self.generation(of: .tickets) == generation else { return }
        ticketsStage = .shown(shown)
        feedback.play(.light)
        noteConfirmed(.tickets)
    }

    private func noteConfirmed(_ module: OpeningPanelModuleID) {
        guard isPowered, !hasDeparted else { return }
        confirmation[module] = .confirmed
        locks.insert(module.meter)
        showCheck(module.meter, step: 0, generation: generation(of: module), module: module)
        let ready = OpeningPanelModuleID.bootOrder.allSatisfy { confirmation(of: $0) == .confirmed }
        isReady = ready
    }

    private func showCheck(
        _ meter: OpeningPanelMeter,
        step: Int,
        generation: Int,
        module: OpeningPanelModuleID?
    ) {
        guard generationMatches(generation, module: module) else { return }
        checkSteps[meter] = step
        guard step < OpeningPanelTiming.checkBlinkLast else { return }
        let next = step + 1
        let delay = OpeningPanelTiming.checkBlink
        if let module {
            after(delay, module: module, generation: generation) { state in
                state.showCheck(meter, step: next, generation: generation, module: module)
            }
        } else {
            afterPower(delay, generation: generation) { state in
                state.showCheck(meter, step: next, generation: generation, module: nil)
            }
        }
    }

    private func rearmAuto() {
        cancelAuto()
        guard isPowered, !hasDeparted, nextAutomaticModule != nil else { return }
        let task = scheduler.schedule(after: OpeningPanelTiming.autoWait) { [weak self] in
            self?.beginAutoChain()
        }
        autoTasks.append(task)
    }

    private func beginAutoChain() {
        guard isPowered, !hasDeparted else { return }
        let pending = OpeningPanelModuleID.bootOrder.filter { confirmation(of: $0) == .unconfirmed }
        guard let first = pending.first else { return }
        feedback.play(.light)
        begin(first)
        for (offset, module) in pending.dropFirst().enumerated() {
            let delay = OpeningPanelTiming.autoGap * Double(offset + 1)
            let task = scheduler.schedule(after: delay) { [weak self] in
                guard let self, self.isPowered, !self.hasDeparted else { return }
                guard self.confirmation(of: module) == .unconfirmed else { return }
                self.feedback.play(.light)
                self.begin(module)
            }
            autoTasks.append(task)
        }
    }

    private func beginDepart() {
        hasDeparted = true
        cancelAuto()
        invalidatePower()
        for module in OpeningPanelModuleID.allCases {
            _ = bump(module)
        }
        lampCheck = .done
        powerLEDCount = OpeningPanelTiming.ledCount
        powerSettled = true

        let meters: [OpeningPanelMeter] = [.master, .clock, .timetable, .tickets]
        for (index, meter) in meters.enumerated() where locks.contains(meter) {
            let delay = Double(index) * OpeningPanelTiming.departLockStagger
            if delay == 0 {
                locks.remove(meter)
            } else {
                departTasks.append(scheduler.schedule(after: delay) { [weak self] in
                    self?.locks.remove(meter)
                })
            }
        }

        departBarDepth = 1
        if OpeningPanelTiming.departBarSteps > 1 {
            for step in 2...OpeningPanelTiming.departBarSteps {
                let delay = Double(step - 1) * OpeningPanelTiming.departBarStep
                departTasks.append(scheduler.schedule(after: delay) { [weak self] in
                    self?.departBarDepth = step
                })
            }
        }

        if !reducesMotion {
            scheduleChevrons()
        }

        let faces = Array(OpeningPanelFace.allCases.reversed())
        for (index, face) in faces.enumerated() {
            let start = OpeningPanelTiming.departSweepLead + Double(index) * OpeningPanelTiming.departModuleStagger
            departTasks.append(scheduler.schedule(after: start) { [weak self] in
                self?.glowingFaces.insert(face)
            })
            departTasks.append(scheduler.schedule(after: start + OpeningPanelTiming.departModuleGlow) { [weak self] in
                self?.glowingFaces.remove(face)
            })
        }
        departTasks.append(scheduler.schedule(after: OpeningPanelTiming.departSweepLead) { [weak self] in
            self?.powerLEDCount = OpeningPanelTiming.ledCount
        })
        departTasks.append(scheduler.schedule(after: OpeningPanelTiming.hubSwitch) { [weak self] in
            self?.onShowHub()
        })
    }

    private func scheduleChevrons() {
        var time = OpeningPanelTiming.chevronLead
        for (index, step) in OpeningPanelTiming.chevronSteps.enumerated() {
            let fire = time
            let fill = index + 1
            departTasks.append(scheduler.schedule(after: fire) { [weak self] in
                self?.chevronFill = fill
            })
            time += step
        }
        let columnOn = time
        departTasks.append(scheduler.schedule(after: columnOn) { [weak self] in
            self?.departColumnLit = true
        })
        departTasks.append(scheduler.schedule(after: columnOn + OpeningPanelTiming.departColumnFlash) { [weak self] in
            self?.departColumnLit = false
        })
    }

    @discardableResult
    private func bump(_ module: OpeningPanelModuleID) -> Int {
        let next = generation(of: module) + 1
        generations[module] = next
        moduleTasks[module]?.forEach { $0.cancel() }
        moduleTasks[module] = []
        return next
    }

    @discardableResult
    private func invalidatePower() -> Int {
        powerGeneration += 1
        let generation = powerGeneration
        powerTasks.forEach { $0.cancel() }
        powerTasks = []
        return generation
    }

    private func cancelAuto() {
        autoTasks.forEach { $0.cancel() }
        autoTasks.removeAll()
    }

    private func cancelDepart() {
        departTasks.forEach { $0.cancel() }
        departTasks.removeAll()
    }

    private func generationMatches(_ generation: Int, module: OpeningPanelModuleID?) -> Bool {
        if let module {
            return self.generation(of: module) == generation
        }
        return powerGeneration == generation
    }

    private func after(
        _ seconds: TimeInterval,
        module: OpeningPanelModuleID,
        generation: Int,
        _ body: @escaping (OpeningPanelState) -> Void
    ) {
        let task = scheduler.schedule(after: seconds) { [weak self] in
            guard let self else { return }
            guard self.generation(of: module) == generation else { return }
            body(self)
        }
        moduleTasks[module, default: []].append(task)
    }

    private func afterPower(
        _ seconds: TimeInterval,
        generation: Int,
        _ body: @escaping (OpeningPanelState) -> Void
    ) {
        let task = scheduler.schedule(after: seconds) { [weak self] in
            guard let self else { return }
            guard self.powerGeneration == generation else { return }
            body(self)
        }
        powerTasks.append(task)
    }
}
