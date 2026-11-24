//
//  OpeningPanelGrid.swift
//  Todo train
//
//  盤の格子。地は設計寸法で描き、窓の中身だけを差し込む。
//

import SwiftUI

/// 運行開始の盤。格子 372×782 を、安全領域の内側へ縦横同じ倍率で収める。
struct OpeningPanelGrid: View {
    private let check: AnyView
    private let phone: AnyView
    private let master: AnyView
    private let clock: AnyView
    private let clockKey: AnyView
    private let hourMode: AnyView
    private let scaleToggle: AnyView
    private let timetableTitle: AnyView
    private let range: AnyView
    private let runStatusTitle: AnyView
    private let timetable: AnyView
    private let runStatus: AnyView
    private let nextStop: AnyView
    private let nextRide: AnyView
    private let timetableKey: AnyView
    private let nowLegend: AnyView
    private let nowBoard: AnyView
    private let sequenceKey: AnyView
    private let ticketsKey: AnyView
    private let ticketsLeading: AnyView
    private let tickets: AnyView
    private let load: AnyView
    private let commTest: AnyView
    private let comm: AnyView
    private let departLock: AnyView
    private let departStatus: AnyView
    private let departFirst: AnyView
    private let departChevrons: AnyView
    private let departBar: AnyView
    private let departLocks: OpeningPanelLockPicture
    private let chevronsFlowing: Bool
    private let departColumnLit: Bool
    private let glowingModules: Set<OpeningPanelTokens.Module>
    private let lamps: OpeningPanelLampField
    private let commTesting: Bool
    private let loadLit: Bool
    private let loadFrameTop: CGFloat
    private let sequenceLit: Bool
    private let ticketReadout: String
    private let ticketReadoutLit: Bool
    private let pileKeys: [OpeningPanelPileKeyState]
    private let onPileKey: (Int) -> Void
    private let todayRows: Int
    private let timetableTwentyFour: Bool
    private let sequenceMode: OpeningPanelHitLayout.SequenceMode?

    @State private var hitActions = OpeningPanelHitActions()
    @Environment(\.openingPanelHitBounds) private var hitBoundsRequested

    init(
        @ViewBuilder check: () -> some View = { EmptyView() },
        @ViewBuilder phone: () -> some View = { EmptyView() },
        @ViewBuilder master: () -> some View = { OpeningPanelMasterAssembly() },
        @ViewBuilder clock: () -> some View = { EmptyView() },
        @ViewBuilder clockKey: () -> some View = { OpeningPanelConfirmKey() },
        @ViewBuilder hourMode: () -> some View = { EmptyView() },
        @ViewBuilder scaleToggle: () -> some View = { EmptyView() },
        @ViewBuilder timetableTitle: () -> some View = { EmptyView() },
        @ViewBuilder range: () -> some View = { EmptyView() },
        @ViewBuilder runStatusTitle: () -> some View = { EmptyView() },
        @ViewBuilder timetable: () -> some View = { EmptyView() },
        @ViewBuilder runStatus: () -> some View = { EmptyView() },
        @ViewBuilder nextStop: () -> some View = { EmptyView() },
        @ViewBuilder nextRide: () -> some View = { EmptyView() },
        @ViewBuilder timetableKey: () -> some View = { EmptyView() },
        @ViewBuilder nowLegend: () -> some View = { EmptyView() },
        @ViewBuilder nowBoard: () -> some View = { EmptyView() },
        @ViewBuilder sequenceKey: () -> some View = { EmptyView() },
        @ViewBuilder ticketsKey: () -> some View = { EmptyView() },
        @ViewBuilder ticketsLeading: () -> some View = { EmptyView() },
        @ViewBuilder tickets: () -> some View = { EmptyView() },
        @ViewBuilder load: () -> some View = { EmptyView() },
        @ViewBuilder commTest: () -> some View = { EmptyView() },
        @ViewBuilder comm: () -> some View = { EmptyView() },
        @ViewBuilder departLock: () -> some View = { EmptyView() },
        @ViewBuilder departStatus: () -> some View = { EmptyView() },
        @ViewBuilder departFirst: () -> some View = { EmptyView() },
        @ViewBuilder departChevrons: () -> some View = { OpeningPanelChevronRow() },
        @ViewBuilder departBar: () -> some View = { OpeningPanelDepartLabel() },
        departLocks: OpeningPanelLockPicture = OpeningPanelLockPicture(),
        chevronsFlowing: Bool = false,
        departColumnLit: Bool = false,
        glowingModules: Set<OpeningPanelTokens.Module> = [],
        lamps: OpeningPanelLampField = OpeningPanelLampField(),
        commTesting: Bool = false,
        loadLit: Bool = false,
        loadFrameTop: CGFloat = 0.36,
        sequenceLit: Bool = false,
        ticketReadout: String = "",
        ticketReadoutLit: Bool = false,
        pileKeys: [OpeningPanelPileKeyState] = OpeningPanelPileKeyState.idle,
        onPileKey: @escaping (Int) -> Void = { _ in },
        todayRows: Int = 5,
        timetableTwentyFour: Bool = false,
        sequenceMode: OpeningPanelHitLayout.SequenceMode? = nil
    ) {
        self.check = AnyView(check())
        self.phone = AnyView(phone())
        self.master = AnyView(master())
        self.clock = AnyView(clock())
        self.clockKey = AnyView(clockKey())
        self.hourMode = AnyView(hourMode())
        self.scaleToggle = AnyView(scaleToggle())
        self.timetableTitle = AnyView(timetableTitle())
        self.range = AnyView(range())
        self.runStatusTitle = AnyView(runStatusTitle())
        self.timetable = AnyView(timetable())
        self.runStatus = AnyView(runStatus())
        self.nextStop = AnyView(nextStop())
        self.nextRide = AnyView(nextRide())
        self.timetableKey = AnyView(timetableKey())
        self.nowLegend = AnyView(nowLegend())
        self.nowBoard = AnyView(nowBoard())
        self.sequenceKey = AnyView(sequenceKey())
        self.ticketsKey = AnyView(ticketsKey())
        self.ticketsLeading = AnyView(ticketsLeading())
        self.tickets = AnyView(tickets())
        self.load = AnyView(load())
        self.commTest = AnyView(commTest())
        self.comm = AnyView(comm())
        self.departLock = AnyView(departLock())
        self.departStatus = AnyView(departStatus())
        self.departFirst = AnyView(departFirst())
        self.departChevrons = AnyView(departChevrons())
        self.departBar = AnyView(departBar())
        self.departLocks = departLocks
        self.chevronsFlowing = chevronsFlowing
        self.departColumnLit = departColumnLit
        self.glowingModules = glowingModules
        self.lamps = lamps
        self.commTesting = commTesting
        self.loadLit = loadLit
        self.loadFrameTop = loadFrameTop
        self.sequenceLit = sequenceLit
        self.ticketReadout = ticketReadout
        self.ticketReadoutLit = ticketReadoutLit
        self.pileKeys = pileKeys
        self.onPileKey = onPileKey
        self.todayRows = todayRows
        self.timetableTwentyFour = timetableTwentyFour
        self.sequenceMode = sequenceMode
    }

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelGrid")
        latticeBody
    }

    private var latticeBody: some View {
        GeometryReader { proxy in
            let _ = OpeningPanelRedrawProbe.bump("gridGeometry")
            let safe = CGRect(origin: .zero, size: proxy.size)
            let placed = TrainLayout.openingPanelPlacement(in: safe)
            let scale = placed.scale
            let minimum = OpeningPanelHitLayout.minimumScreen / max(scale, 0.01)
            lattice(minimum: minimum)
                .environment(\.openingPanelHitMinimum, minimum)
                .frame(
                    width: OpeningPanelTokens.Canvas.width,
                    height: OpeningPanelTokens.Canvas.height
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: placed.size.width, height: placed.size.height, alignment: .topLeading)
                .position(
                    x: placed.origin.x + placed.size.width / 2,
                    y: placed.origin.y + placed.size.height / 2
                )
        }
        .environment(\.openingPanelRoutesHits, true)
        .environment(\.openingPanelHitActions, hitActions)
        .background {
            OpeningPanelTokens.Palette.housing.ignoresSafeArea()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("運行開始の盤")
    }

    private var showsHitBounds: Bool {
        hitBoundsRequested || ProcessInfo.processInfo.arguments.contains("-OpeningPanelHitBounds")
    }

    private func lattice(minimum: CGFloat) -> some View {
        let targets = OpeningPanelHitLayout.board(
            minimum: minimum,
            ticketRows: todayRows,
            sequence: sequenceMode
        )
        return OpeningPanelLattice {
            cell(.sysbar) { sysbar }
            cell(.master) { masterModule }
            cell(.clock) { clockModule }
            cell(.clockKey) { clockKeyModule }
            cell(.timetable) { timetableModule }
            cell(.nowBoard) { nowModule }
            cell(.tickets) { ticketsModule }
            cell(.load) { loadModule }
            cell(.comm) { commModule }
            cell(.depart) { departModule }
        }
        .frame(
            width: OpeningPanelTokens.Canvas.width,
            height: OpeningPanelTokens.Canvas.height,
            alignment: .topLeading
        )
        .background(OpeningPanelTokens.Palette.grid)
        .overlay {
            OpeningPanelHitOverlay(targets: targets, actions: hitActions)
        }
        .overlay {
            if showsHitBounds {
                OpeningPanelHitBounds(targets: targets)
            }
        }
        .clipped()
    }

    private func cell<V: View>(
        _ module: OpeningPanelTokens.Module,
        @ViewBuilder content: () -> V
    ) -> some View {
        let frame = module.frame()
        return content()
            .frame(width: frame.width, height: frame.height, alignment: .topLeading)
            .clipped()
    }

    private var sysbar: some View {
        HStack(spacing: OpeningPanelTokens.Chrome.stripSplit) {
            OpeningPanelModule(
                tone: .standard,
                alignment: .center,
                glowing: glowingModules.contains(.sysbar)
            ) {
                OpeningPanelCenterRow {
                    HStack(spacing: 4) {
                        OpeningPanelLegend(
                            text: "CHK",
                            size: 7,
                            tracking: 0.14,
                            padding: EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3)
                        )
                        lampPair("MSTR", style: lamps.master)
                        lampPair("CLK", style: lamps.clock)
                        lampPair("TT", style: lamps.timetable)
                        lampPair("TKT", style: lamps.tickets)
                        check
                    }
                    .padding(.horizontal, 5)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CHK")

            OpeningPanelModule(
                tone: .standard,
                alignment: .center,
                glowing: glowingModules.contains(.sysbar)
            ) {
                OpeningPanelCenterRow {
                    HStack(spacing: 4) {
                        OpeningPanelLegend(
                            text: "PHONE",
                            size: 7,
                            tracking: 0.14,
                            padding: EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3)
                        )
                        OpeningPanelWindow(exposesContent: true) { phone }
                            .frame(width: 36, height: OpeningPanelTokens.Chrome.phoneWindowHeight)
                        lampPair("EXT", style: lamps.ext)
                        lampPair("AWAKE", style: lamps.awake)
                    }
                    .padding(.horizontal, 5)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("PHONE")
        }
    }

    private func lampPair(_ name: String, style: OpeningPanelLampStyle) -> some View {
        HStack(spacing: 2) {
            OpeningPanelLamp(style: style)
            Text(name)
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.14)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue(style.spoken)
    }

    private var masterModule: some View {
        OpeningPanelModule(tone: .upper, glowing: glowingModules.contains(.master)) {
            master
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MASTER")
    }

    private var clockModule: some View {
        OpeningPanelModule(tone: .upper, glowing: glowingModules.contains(.clock)) {
            OpeningPanelWindow(exposesContent: true) { clock }
                .padding(6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("時計")
    }

    private var clockKeyModule: some View {
        OpeningPanelModule(tone: .upper, glowing: glowingModules.contains(.clockKey)) {
            VStack(spacing: 0) {
                OpeningPanelLegend(text: "CLOCK")
                Spacer(minLength: 4)
                clockKey
                    .frame(
                        width: OpeningPanelTokens.Chrome.clockKeySize.width,
                        height: OpeningPanelTokens.Chrome.clockKeySize.height
                    )
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    ZStack {
                        OpeningPanelCap()
                        hourMode
                    }
                    .frame(width: 18, height: 18)
                    Text("12/24")
                        .font(OpeningPanelFaceFont.legend(8))
                        .tracking(0.4)
                        .foregroundStyle(OpeningPanelTokens.Palette.legend)
                        .lineLimit(1)
                }
            }
            .padding(EdgeInsets(top: 8, leading: 6, bottom: 6, trailing: 6))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CLOCK")
    }

    private var timetableModule: some View {
        OpeningPanelModule(tone: .standard, glowing: glowingModules.contains(.timetable)) {
            VStack(spacing: 3) {
                timetableHeader
                timetableRow
                timetableFooter
            }
            .padding(EdgeInsets(top: 6, leading: 8, bottom: 5, trailing: 6))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TIMETABLE")
    }

    private var timetableHeader: some View {
        HStack(spacing: 6) {
            OpeningPanelLegend(text: "TIMETABLE")
            timetableTitle
            ZStack {
                OpeningPanelScaleToggle(twentyFour: timetableTwentyFour)
                scaleToggle
            }
            OpeningPanelWindow(exposesContent: true) { range }
                .frame(
                    width: OpeningPanelTokens.Chrome.rangeWindow.width,
                    height: OpeningPanelTokens.Chrome.rangeWindow.height
                )
            Spacer(minLength: 0)
            OpeningPanelLegend(text: "運転状況")
                .frame(width: OpeningPanelTokens.RunStatus.width)
                .padding(.trailing, 20)
            runStatusTitle
        }
        .frame(height: 22)
    }

    private var timetableRow: some View {
        HStack(spacing: OpeningPanelTokens.RunStatus.columnGap) {
            OpeningPanelWindow(exposesContent: true) { timetable }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OpeningPanelWindow(label: "運転状況", exposesContent: true) { runStatus }
                .frame(width: OpeningPanelTokens.RunStatus.width)
        }
        .frame(maxHeight: .infinity)
    }

    private var timetableFooter: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                OpeningPanelNextPair()
                VStack(alignment: .leading, spacing: 2) {
                    nextStop
                    nextRide
                }
            }
            Spacer(minLength: 0)
            ZStack {
                OpeningPanelConfirmKey()
                timetableKey
            }
            .frame(width: 52, height: 30)
        }
        .frame(height: 30)
    }

    private var nowModule: some View {
        OpeningPanelModule(tone: .standard, glowing: glowingModules.contains(.nowBoard)) {
            HStack(spacing: 6) {
                OpeningPanelLegend(text: "ただいま")
                nowLegend
                OpeningPanelWindow { nowBoard }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ただいま")
    }

    private var ticketsModule: some View {
        OpeningPanelModule(tone: .lower, glowing: glowingModules.contains(.tickets)) {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    OpeningPanelLegend(text: "TICKETS")
                    OpeningPanelWindow {
                        Text(ticketReadout)
                            .font(.system(size: 9))
                            .tracking(0.36)
                            .foregroundStyle(OpeningPanelTokens.Palette.amber)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.horizontal, 5)
                            .opacity(ticketReadoutLit ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 18)
                    .accessibilityLabel("TODAY")
                    .accessibilityValue(ticketReadoutLit ? ticketReadout : "")
                    ZStack {
                        OpeningPanelSeqKey(lit: sequenceLit)
                            .accessibilityHidden(true)
                        sequenceKey
                    }
                    .frame(width: 36, height: 20)
                    ZStack {
                        OpeningPanelConfirmKey()
                            .accessibilityHidden(true)
                        ticketsKey
                    }
                    .frame(width: 64, height: 30)
                }
                .frame(height: 30)
                HStack(alignment: .top, spacing: 4) {
                    ticketsLeading
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                    OpeningPanelWindow(exposesContent: true) { tickets }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    pileColumn
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TICKETS")
    }

    private var pileColumn: some View {
        VStack(spacing: OpeningPanelSequenceLayout.keyGap) {
            ForEach(pileKeys) { key in
                Button {
                    onPileKey(key.id)
                } label: {
                    OpeningPanelPileKeyFace(title: key.title, count: key.count, lit: key.lit)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .openingPanelAction(.sequencePile(key.id)) { onPileKey(key.id) }
                .accessibilityLabel(key.title.isEmpty ? "消灯" : key.title)
                .accessibilityValue(key.count)
                .accessibilityHint(pileHint(key))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: OpeningPanelSequenceLayout.keyWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func pileHint(_ key: OpeningPanelPileKeyState) -> String {
        guard key.lit else { return "このキーは使えません" }
        switch key.title {
        case "上が先":
            return "上の切符を先にします"
        case "下が先":
            return "下の切符を先にします"
        default:
            return "この山に入れます"
        }
    }

    private var loadModule: some View {
        OpeningPanelModule(tone: .standard, glowing: glowingModules.contains(.load)) {
            VStack(alignment: .leading, spacing: 4) {
                OpeningPanelLegend(text: "LOAD")
                OpeningPanelLoadFace(lit: loadLit, frameTop: loadFrameTop) {
                    load
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(EdgeInsets(top: 8, leading: 6, bottom: 6, trailing: 6))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("LOAD")
    }

    private var commModule: some View {
        OpeningPanelModule(tone: .standard, glowing: glowingModules.contains(.comm)) {
            HStack(spacing: 4) {
                OpeningPanelLegend(
                    text: "COMM",
                    size: 7,
                    tracking: 0.14,
                    padding: EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3),
                    strip: OpeningPanelTokens.Palette.commStrip
                )
                ZStack {
                    OpeningPanelCap(side: 16, sunk: commTesting)
                    commTest
                }
                .frame(width: 16, height: 16)
                Text("TEST")
                    .font(OpeningPanelFaceFont.legend(7))
                    .tracking(0.14)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                    .lineLimit(1)
                OpeningPanelWindow(exposesContent: true) { comm }
                    .frame(height: OpeningPanelTokens.Chrome.commWindowHeight)
                lampPair("RELAY", style: lamps.relay)
                lampPair("MAC", style: lamps.mac)
            }
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("COMM")
    }

    private var departModule: some View {
        // 波の時刻は矢羽根の Canvas と、当たった瞬間の輪だけが見る。
        departFace(columnLit: departColumnLit)
    }

    private func departFace(columnLit: Bool) -> some View {
        let _ = OpeningPanelRedrawProbe.bump("departFace")
        return OpeningPanelModule(tone: .lower, glowing: glowingModules.contains(.depart)) {
            HStack(alignment: .center, spacing: 6) {
                VStack(spacing: 3) {
                    ZStack {
                        OpeningPanelLockRow(picture: departLocks)
                        departLock
                    }
                    .frame(height: 11)
                    OpeningPanelWindow { departStatus }
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                    OpeningPanelWindow(exposesContent: true) { departFirst }
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                    OpeningPanelChevronWell()
                        .frame(height: OpeningPanelTokens.Chrome.chevronWellHeight)
                        .overlay {
                            departChevrons
                                .padding(3)
                        }
                }
                .frame(width: OpeningPanelTokens.Chrome.departReadoutWidth, alignment: .top)
                OpeningPanelPushBar(columnLit: columnLit, chevronsFlowing: chevronsFlowing) {
                    departBar
                }
                .frame(width: OpeningPanelTokens.Chrome.departBar.width)
                .frame(maxHeight: .infinity)
            }
            .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DEPART")
    }
}

/// 盛り上がったモジュールの面。縁は平面の髪の毛。
struct OpeningPanelModule<Content: View>: View {
    var tone: OpeningPanelTokens.FaceTone
    var alignment: Alignment = .top
    /// `.mod.rp`。縁の走査が当たっているあいだだけ。
    var glowing = false
    private var content: Content

    init(
        tone: OpeningPanelTokens.FaceTone,
        alignment: Alignment = .top,
        glowing: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.alignment = alignment
        self.glowing = glowing
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(tone.fill)
            .overlay { edges }
    }

    @ViewBuilder
    private var edges: some View {
        if glowing {
            Rectangle()
                .strokeBorder(OpeningPanelTokens.Palette.moduleSweep, lineWidth: 1)
        } else {
            Rectangle()
                .strokeBorder(
                    OpeningPanelTokens.Palette.moduleEdgeOuter,
                    lineWidth: OpeningPanelTokens.Chrome.hairline
                )
            Rectangle()
                .strokeBorder(
                    OpeningPanelTokens.Palette.moduleEdgeInner,
                    lineWidth: OpeningPanelTokens.Chrome.hairline
                )
                .padding(OpeningPanelTokens.Chrome.hairline)
        }
    }
}

/// 凹んだ窓。表示だけで、中身を差し込める。
struct OpeningPanelWindow<Content: View>: View {
    var label: String?
    /// 中身が自分の読み上げを持つとき。時計の時刻に使う。
    var exposesContent = false
    private var content: Content

    init(label: String? = nil, exposesContent: Bool = false, @ViewBuilder content: () -> Content) {
        self.label = label
        self.exposesContent = exposesContent
        self.content = content()
    }

    var body: some View {
        let chrome = ZStack {
            RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.windowRadius, style: .continuous)
                .fill(OpeningPanelTokens.Palette.window)
            RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.windowRadius, style: .continuous)
                .strokeBorder(OpeningPanelTokens.Palette.windowEdge, lineWidth: 1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if exposesContent {
            if let label, !label.isEmpty {
                chrome
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(label)
            } else {
                chrome.accessibilityElement(children: .contain)
            }
        } else {
            chrome
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label ?? "")
                .accessibilityHidden(label == nil)
        }
    }
}

/// 盛り上がった操作面。下に平面の唇を付け、レンズへ中身を差し込める。
struct OpeningPanelRaisedControl<Content: View>: View {
    enum Style {
        case key
        case cap
    }

    var style: Style = .key
    private var content: Content

    init(style: Style = .key, @ViewBuilder content: () -> Content) {
        self.style = style
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            face
            Rectangle()
                .fill(style == .key ? OpeningPanelTokens.Palette.raisedLip : OpeningPanelTokens.Palette.capLip)
                .frame(height: OpeningPanelTokens.Chrome.controlLip)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var face: some View {
        switch style {
        case .key:
            ZStack {
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.raised)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OpeningPanelTokens.Palette.lens)
                    .padding(OpeningPanelTokens.Chrome.controlPadding)
            }
        case .cap:
            ZStack {
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.capRingOuter)
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.capRing)
                    .padding(2)
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.cap)
                    .padding(3)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(3)
            }
        }
    }
}

/// DEPART の押し棒。同心の輪は枠の外へ 4。
struct OpeningPanelPushBar<Content: View>: View {
    var columnLit = false
    var chevronsFlowing = false
    private var content: Content

    init(
        columnLit: Bool = false,
        chevronsFlowing: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.columnLit = columnLit
        self.chevronsFlowing = chevronsFlowing
        self.content = content()
    }

    var body: some View {
        let _ = OpeningPanelRedrawProbe.bump("OpeningPanelPushBar")
        VStack(spacing: 2) {
            housing
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("DEPART")
                .font(OpeningPanelFaceFont.legend(6))
                .tracking(0.3)
                .foregroundStyle(OpeningPanelTokens.Palette.engraved)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .accessibilityElement(children: .contain)
    }

    private var housing: some View {
        content
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpeningPanelTokens.Palette.barHousing)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(OpeningPanelTokens.Palette.barRingInner, lineWidth: 1)
                    .padding(-4)
            }
            .overlay {
                DepartColumnRing(baseLit: columnLit, flowing: chevronsFlowing)
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.black.opacity(0.6), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 5)
                .offset(y: 1)
                .mask(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(OpeningPanelTokens.Palette.barRing, lineWidth: 1)
                    .padding(-1)
            }
    }
}

/// 22pt の帯では安全領域が中身を枠の外へ押し出す。理想サイズのまま縦の中央に置く。
private struct OpeningPanelCenterRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: bounds.width, height: size.height)
        )
    }
}

/// 格子の外枠いっぱいにモジュールを置く。提案サイズを各枠の寸法に固定する。
private struct OpeningPanelLattice: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        OpeningPanelTokens.Canvas.outer
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let _ = OpeningPanelRedrawProbe.bump("latticeLayout")
        for (module, subview) in zip(OpeningPanelTokens.Module.allCases, subviews) {
            let frame = module.frame()
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }
}

/// 空の盤面で見せる、押していない矢羽根。
struct OpeningPanelChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.52, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct OpeningPanelChevronRow: View {
    var count: Int = OpeningPanelTokens.Chrome.chevronCount

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in
                OpeningPanelChevron()
                    .fill(OpeningPanelTokens.Palette.chevron)
            }
        }
        .accessibilityHidden(true)
    }
}

final class OpeningPanelHitActions {
    var taps: [OpeningPanelHitLayout.ID: () -> Void] = [:]

    func set(_ id: OpeningPanelHitLayout.ID, _ action: @escaping () -> Void) {
        taps[id] = action
    }

    func perform(_ id: OpeningPanelHitLayout.ID) {
        taps[id]?()
    }
}

private struct OpeningPanelRoutesHitsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct OpeningPanelHitActionsKey: EnvironmentKey {
    static let defaultValue = OpeningPanelHitActions()
}

private struct OpeningPanelHitBoundsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct OpeningPanelHitMinimumKey: EnvironmentKey {
    static let defaultValue = OpeningPanelHitLayout.minimumScreen
}

extension EnvironmentValues {
    var openingPanelRoutesHits: Bool {
        get { self[OpeningPanelRoutesHitsKey.self] }
        set { self[OpeningPanelRoutesHitsKey.self] = newValue }
    }

    var openingPanelHitActions: OpeningPanelHitActions {
        get { self[OpeningPanelHitActionsKey.self] }
        set { self[OpeningPanelHitActionsKey.self] = newValue }
    }

    /// 当たりの外形。既定はオフ。起動引数 `-OpeningPanelHitBounds` でも点く。
    var openingPanelHitBounds: Bool {
        get { self[OpeningPanelHitBoundsKey.self] }
        set { self[OpeningPanelHitBoundsKey.self] = newValue }
    }

    /// 設計寸法での当たりの下限。画面上で 44pt になるよう、格子の倍率で割った値。
    var openingPanelHitMinimum: CGFloat {
        get { self[OpeningPanelHitMinimumKey.self] }
        set { self[OpeningPanelHitMinimumKey.self] = newValue }
    }
}

extension View {
    func openingPanelAction(
        _ id: OpeningPanelHitLayout.ID,
        perform: @escaping () -> Void
    ) -> some View {
        modifier(OpeningPanelActionModifier(id: id, perform: perform))
    }
}

private struct OpeningPanelActionModifier: ViewModifier {
    @Environment(\.openingPanelRoutesHits) private var routed
    var id: OpeningPanelHitLayout.ID
    var perform: () -> Void

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!routed)
            .background {
                if routed {
                    OpeningPanelActionSink(id: id, perform: perform)
                }
            }
    }
}

private struct OpeningPanelActionSink: View {
    @Environment(\.openingPanelHitActions) private var actions
    var id: OpeningPanelHitLayout.ID
    var perform: () -> Void

    var body: some View {
        let _ = actions.set(id, perform)
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onDisappear { actions.taps[id] = nil }
    }
}

private struct OpeningPanelPileKeyFace: View {
    var title: String
    var count: String
    var lit: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !count.isEmpty {
                Text(count)
                    .font(.system(size: 9))
                    .monospacedDigit()
                    .opacity(0.85)
            }
        }
        .foregroundStyle(lit ? OpeningPanelTokens.Palette.amber : OpeningPanelTokens.Palette.keySegInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(lit ? OpeningPanelTokens.Palette.key(0x4A3A14) : OpeningPanelTokens.Palette.key(0x2F3133))
        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OpeningPanelTokens.Palette.key(0x2E3033))
        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OpeningPanelTokens.Palette.key(0x1D1E20))
                .frame(height: 2)
                .offset(y: 2)
        }
    }
}

private struct OpeningPanelHitOverlay: View {
    var targets: [OpeningPanelHitLayout.Target]
    var actions: OpeningPanelHitActions

    var body: some View {
        ZStack {
            ForEach(targets) { target in
                pad(target)
            }
        }
        .frame(
            width: OpeningPanelTokens.Canvas.width,
            height: OpeningPanelTokens.Canvas.height,
            alignment: .topLeading
        )
    }

    private func pad(_ target: OpeningPanelHitLayout.Target) -> some View {
        let rect = target.hit
        return Color.clear
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture { actions.perform(target.id) }
            .position(x: rect.midX, y: rect.midY)
    }
}

private struct OpeningPanelHitBounds: View {
    var targets: [OpeningPanelHitLayout.Target]

    var body: some View {
        ZStack {
            ForEach(targets) { target in
                Rectangle()
                    .stroke(OpeningPanelTokens.Palette.engraved, lineWidth: 1)
                    .frame(width: target.hit.width, height: target.hit.height)
                    .position(x: target.hit.midX, y: target.hit.midY)
            }
        }
        .frame(
            width: OpeningPanelTokens.Canvas.width,
            height: OpeningPanelTokens.Canvas.height,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

#Preview("確認済み・待機") {
    WaitingTicketsPreview()
        .frame(
            width: OpeningPanelTokens.Phone.width,
            height: OpeningPanelTokens.Phone.height
        )
        .background(Color.black)
}

#Preview("空の盤面") {
    OpeningPanelGrid()
        .frame(
            width: OpeningPanelTokens.Phone.width,
            height: OpeningPanelTokens.Phone.height
        )
        .background(Color.black)
}

#Preview("狭い枠") {
    OpeningPanelGrid()
        .frame(width: 320, height: 640)
        .background(Color.black)
}

/// 確認済みで、仕分けに入る前の TICKETS。番号の枠、切れ目、日数、見積もり/実績、右のキー。
private struct WaitingTicketsPreview: View {
    var body: some View {
        let sample = Sample.make()
        OpeningPanelGrid(
            tickets: { TicketsModule(state: sample.state, model: sample.model) },
            ticketReadout: OpeningPanelTickets.readout(
                today: sample.model.cut,
                total: sample.model.rows.count,
                freeMinutes: sample.freeMinutes
            ),
            ticketReadoutLit: sample.state.isPowered
                && sample.state.confirmation(of: .tickets) == .confirmed,
            todayRows: OpeningPanelSequenceMath.visibleSpan(
                line: sample.model.cut,
                total: sample.model.rows.count
            ).shown
        )
    }

    private struct Sample {
        var state: OpeningPanelState
        var model: OpeningPanelTicketsModel
        var freeMinutes: Int

        @MainActor
        static func make() -> Sample {
            let specs: [(title: String, minutes: Int, days: Int, rides: [Int]?)] = [
                ("報告書", 25, 0, [22, 28, 24]),
                ("メール", 10, 0, nil),
                ("図面", 40, 0, [36, 44, 38]),
                ("会議メモ", 15, 2, nil),
                ("買い出し", 20, 1, [18, 21, 19]),
                ("読書", 30, 4, nil),
                ("掃除", 25, 0, nil),
                ("返信", 10, 3, nil),
            ]
            var tickets: [Ticket] = []
            var sessions: [WorkSession] = []
            var days: [UUID: Int] = [:]
            let now = Date.now
            for (index, spec) in specs.enumerated() {
                let ticket = Ticket(
                    title: spec.title,
                    estimatedSeconds: spec.minutes * 60,
                    sortOrder: index
                )
                tickets.append(ticket)
                if spec.days > 0 {
                    days[ticket.id] = spec.days
                }
                for (ride, minutes) in (spec.rides ?? []).enumerated() {
                    let started = now.addingTimeInterval(-Double((ride + 1) * 86_400))
                    let session = WorkSession(
                        startedAt: started,
                        estimatedSecondsAtStart: spec.minutes * 60,
                        ticket: ticket
                    )
                    session.endedAt = started.addingTimeInterval(Double(minutes * 60))
                    session.outcome = .arrived
                    session.accumulatedActiveSeconds = Double(minutes * 60)
                    sessions.append(session)
                }
            }
            let model = OpeningPanelTicketsModel()
            model.show(tickets: tickets, arrivals: [:], sessions: sessions, daysBelow: days, now: now)
            let scheduler = OpeningPanelPreviewScheduler()
            let state = OpeningPanelState(
                scheduler: scheduler,
                feedback: OpeningPanelFeedbackSilent(),
                ticketCount: model.rows.count,
                reduceMotion: true
            )
            state.pressMaster()
            scheduler.advance(by: 3)
            return Sample(state: state, model: model, freeMinutes: 95)
        }
    }
}
