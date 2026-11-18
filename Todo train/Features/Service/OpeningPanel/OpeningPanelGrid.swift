//
//  OpeningPanelGrid.swift
//  Todo train
//
//  盤の格子と、モジュールの外枠・窓。中身は差し込める。
//  既存の ServiceBootCover はここでは差し替えない。
//

import SwiftUI

/// 運行開始の盤。設計寸法で組み、安全領域に収まらないときだけ縮小する。
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

    init(
        @ViewBuilder check: () -> some View = { EmptyView() },
        @ViewBuilder phone: () -> some View = { EmptyView() },
        @ViewBuilder master: () -> some View = { EmptyView() },
        @ViewBuilder clock: () -> some View = { EmptyView() },
        @ViewBuilder clockKey: () -> some View = { EmptyView() },
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
        @ViewBuilder departBar: () -> some View = { EmptyView() }
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
    }

    var body: some View {
        GeometryReader { proxy in
            let fitted = TrainLayout.openingPanelSize(fitting: proxy.size)
            let scale = fitted.width / OpeningPanelTokens.Canvas.outer.width
            designBoard
                .frame(
                    width: OpeningPanelTokens.Canvas.outer.width,
                    height: OpeningPanelTokens.Canvas.outer.height
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: fitted.width, height: fitted.height, alignment: .topLeading)
                .clipped()
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("運行開始の盤")
    }

    private var designBoard: some View {
        lattice
            .padding(OpeningPanelTokens.Canvas.outerInset)
            .background(OpeningPanelTokens.Palette.grid)
    }

    private var lattice: some View {
        ZStack(alignment: .topLeading) {
            placed(.sysbar) { sysbar }
            placed(.master) { masterModule }
            placed(.clock) { clockModule }
            placed(.clockKey) { clockKeyModule }
            placed(.timetable) { timetableModule }
            placed(.nowBoard) { nowModule }
            placed(.tickets) { ticketsModule }
            placed(.load) { loadModule }
            placed(.comm) { commModule }
            placed(.depart) { departModule }
        }
        .background(OpeningPanelTokens.Palette.grid)
        .frame(
            width: OpeningPanelTokens.Canvas.width,
            height: OpeningPanelTokens.Canvas.height
        )
    }

    private func placed<V: View>(
        _ module: OpeningPanelTokens.Module,
        @ViewBuilder content: () -> V
    ) -> some View {
        let frame = module.frame()
        return content()
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
    }

    private var sysbar: some View {
        HStack(spacing: OpeningPanelTokens.Chrome.stripSplit) {
            OpeningPanelModule(tone: .standard) {
                check
                    .padding(.horizontal, 5)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CHK")

            OpeningPanelModule(tone: .standard) {
                OpeningPanelWindow { phone }
                    .frame(height: OpeningPanelTokens.Chrome.phoneWindowHeight)
                    .padding(.horizontal, 5)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("PHONE")
        }
    }

    private var masterModule: some View {
        OpeningPanelModule(tone: .upper) {
            OpeningPanelRaisedControl { master }
                .padding(8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MASTER")
    }

    private var clockModule: some View {
        OpeningPanelModule(tone: .upper) {
            OpeningPanelWindow { clock }
                .padding(OpeningPanelTokens.Chrome.modulePadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("時計")
    }

    private var clockKeyModule: some View {
        OpeningPanelModule(tone: .upper) {
            VStack(spacing: 6) {
                OpeningPanelRaisedControl { clockKey }
                    .frame(
                        width: OpeningPanelTokens.Chrome.clockKeySize.width,
                        height: OpeningPanelTokens.Chrome.clockKeySize.height
                    )
                OpeningPanelRaisedControl(style: .cap) { hourMode }
                    .frame(
                        width: OpeningPanelTokens.Chrome.hourModeSize.width,
                        height: OpeningPanelTokens.Chrome.hourModeSize.height
                    )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("CLOCK")
    }

    private var timetableModule: some View {
        OpeningPanelModule(tone: .standard) {
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
        HStack(spacing: OpeningPanelTokens.RunStatus.columnGap) {
            HStack(spacing: 6) {
                OpeningPanelRaisedControl { scaleToggle }
                    .frame(
                        width: OpeningPanelTokens.Chrome.scaleToggleSize.width,
                        height: OpeningPanelTokens.Chrome.scaleToggleSize.height
                    )
                timetableTitle
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                OpeningPanelWindow { range }
                    .frame(
                        width: OpeningPanelTokens.Chrome.rangeWindow.width,
                        height: OpeningPanelTokens.Chrome.rangeWindow.height
                    )
            }
            runStatusTitle
                .frame(width: OpeningPanelTokens.RunStatus.width, height: 22)
        }
        .frame(height: 22)
    }

    private var timetableRow: some View {
        GeometryReader { geo in
            let split = OpeningPanelTokens.timetableSplit(
                in: CGRect(origin: .zero, size: geo.size)
            )
            insetWindow(split.timetableWindow, content: split.timetableContent) {
                timetable
            }
            insetWindow(
                split.runStatusWindow,
                content: split.runStatusContent,
                label: "運転状況"
            ) {
                runStatus
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var timetableFooter: some View {
        HStack(spacing: OpeningPanelTokens.RunStatus.columnGap) {
            OpeningPanelWindow { nextStop }
                .frame(
                    width: OpeningPanelTokens.Chrome.nextWindow.width,
                    height: OpeningPanelTokens.Chrome.nextWindow.height
                )
            OpeningPanelWindow { nextRide }
                .frame(
                    width: OpeningPanelTokens.Chrome.nextWindow.width,
                    height: OpeningPanelTokens.Chrome.nextWindow.height
                )
            Spacer(minLength: 0)
            OpeningPanelRaisedControl { timetableKey }
                .frame(
                    width: OpeningPanelTokens.Chrome.timetableKeySize.width,
                    height: OpeningPanelTokens.Chrome.timetableKeySize.height
                )
        }
        .frame(height: OpeningPanelTokens.Chrome.timetableKeySize.height)
    }

    private var nowModule: some View {
        OpeningPanelModule(tone: .standard) {
            HStack(spacing: 6) {
                nowLegend
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                OpeningPanelWindow { nowBoard }
                    .frame(
                        width: OpeningPanelTokens.Chrome.nowWindow.width,
                        height: OpeningPanelTokens.Chrome.nowWindow.height
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("ただいま")
    }

    private var ticketsModule: some View {
        OpeningPanelModule(tone: .lower) {
            VStack(spacing: 5) {
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    OpeningPanelRaisedControl { sequenceKey }
                        .frame(
                            width: OpeningPanelTokens.Chrome.sequenceKeySize.width,
                            height: OpeningPanelTokens.Chrome.sequenceKeySize.height
                        )
                    OpeningPanelRaisedControl { ticketsKey }
                        .frame(
                            width: OpeningPanelTokens.Chrome.ticketsKeySize.width,
                            height: OpeningPanelTokens.Chrome.ticketsKeySize.height
                        )
                }
                .frame(height: OpeningPanelTokens.Chrome.ticketsKeySize.height)
                HStack(spacing: 4) {
                    ticketsLeading
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    OpeningPanelWindow { tickets }
                        .frame(
                            width: OpeningPanelTokens.Chrome.ticketsWindow.width,
                            height: OpeningPanelTokens.Chrome.ticketsWindow.height
                        )
                }
            }
            .padding(OpeningPanelTokens.Chrome.modulePadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TICKETS")
    }

    private var loadModule: some View {
        OpeningPanelModule(tone: .standard) {
            OpeningPanelWindow { load }
                .frame(
                    width: OpeningPanelTokens.Chrome.loadGauge.width,
                    height: OpeningPanelTokens.Chrome.loadGauge.height
                )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("LOAD")
    }

    private var commModule: some View {
        OpeningPanelModule(tone: .standard) {
            HStack(spacing: OpeningPanelTokens.Chrome.commSpacing) {
                OpeningPanelRaisedControl(style: .cap) { commTest }
                    .frame(
                        width: OpeningPanelTokens.Chrome.testSize.width,
                        height: OpeningPanelTokens.Chrome.testSize.height
                    )
                OpeningPanelWindow { comm }
                    .frame(height: OpeningPanelTokens.Chrome.commWindowHeight)
            }
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("COMM")
    }

    private var departModule: some View {
        OpeningPanelModule(tone: .lower) {
            HStack(alignment: .center, spacing: OpeningPanelTokens.Chrome.departGap) {
                VStack(spacing: 3) {
                    departLock
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                    OpeningPanelWindow { departStatus }
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                    OpeningPanelWindow { departFirst }
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                    OpeningPanelWindow { departChevrons }
                        .frame(maxHeight: .infinity)
                }
                .frame(width: OpeningPanelTokens.Chrome.departReadoutWidth)
                OpeningPanelPushBar { departBar }
                    .frame(
                        width: OpeningPanelTokens.Chrome.departBar.width,
                        height: OpeningPanelTokens.Chrome.departBar.height
                    )
            }
            .padding(.horizontal, OpeningPanelTokens.Chrome.departPaddingH)
            .padding(.vertical, OpeningPanelTokens.Chrome.departPaddingV)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("DEPART")
    }

    private func insetWindow<V: View>(
        _ window: CGRect,
        content contentRect: CGRect,
        label: String? = nil,
        @ViewBuilder content: () -> V
    ) -> some View {
        OpeningPanelWindow(label: label) {
            content()
                .padding(EdgeInsets(
                    top: contentRect.minY - window.minY,
                    leading: contentRect.minX - window.minX,
                    bottom: window.maxY - contentRect.maxY,
                    trailing: window.maxX - contentRect.maxX
                ))
        }
        .frame(width: window.width, height: window.height)
        .position(x: window.midX, y: window.midY)
    }
}

/// 盛り上がったモジュールの面。縁は平面の髪の毛。
struct OpeningPanelModule<Content: View>: View {
    var tone: OpeningPanelTokens.FaceTone
    private var content: Content

    init(tone: OpeningPanelTokens.FaceTone, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tone.fill)
            .overlay {
                Rectangle()
                    .strokeBorder(
                        OpeningPanelTokens.Palette.moduleEdgeOuter,
                        lineWidth: OpeningPanelTokens.Chrome.hairline
                    )
            }
            .overlay {
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
    private var content: Content

    init(label: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.windowRadius)
                    .fill(OpeningPanelTokens.Palette.window)
            }
            .overlay {
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.windowRadius)
                    .strokeBorder(OpeningPanelTokens.Palette.windowEdge, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
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
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius)
                    .fill(OpeningPanelTokens.Palette.raised)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(OpeningPanelTokens.Palette.lens)
                    .padding(OpeningPanelTokens.Chrome.controlPadding)
            }
        case .cap:
            ZStack {
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius)
                    .fill(OpeningPanelTokens.Palette.capRingOuter)
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius)
                    .fill(OpeningPanelTokens.Palette.capRing)
                    .padding(2)
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Chrome.controlRadius)
                    .fill(OpeningPanelTokens.Palette.cap)
                    .padding(3)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(3)
            }
        }
    }
}

/// DEPART の押し棒。同心の平面の縁と、下の唇。
struct OpeningPanelPushBar<Content: View>: View {
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpeningPanelTokens.Palette.barRingInner)
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpeningPanelTokens.Palette.barRingMid)
                    .padding(1)
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpeningPanelTokens.Palette.barRing)
                    .padding(3)
                RoundedRectangle(cornerRadius: 4)
                    .fill(OpeningPanelTokens.Palette.barHousing)
                    .padding(4)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(OpeningPanelTokens.Palette.barHighlight)
                        .frame(height: 1)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(OpeningPanelTokens.Palette.barFace)
                    Rectangle()
                        .fill(OpeningPanelTokens.Palette.barShade)
                        .frame(height: 4)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
            }
            Rectangle()
                .fill(OpeningPanelTokens.Palette.barLip)
                .frame(height: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
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
        .padding(3)
        .accessibilityHidden(true)
    }
}

#Preview("空の盤面") {
    OpeningPanelGrid()
        .frame(
            width: OpeningPanelTokens.Canvas.outer.width,
            height: OpeningPanelTokens.Canvas.outer.height
        )
        .background(OpeningPanelTokens.Palette.housing)
}

#Preview("狭い枠") {
    OpeningPanelGrid()
        .frame(width: 320, height: 640)
        .background(OpeningPanelTokens.Palette.housing)
}
