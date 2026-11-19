//
//  OpeningPanelGrid.swift
//  Todo train
//
//  盤の格子。地は設計寸法で描き、窓の中身だけを差し込む。
//

import SwiftUI

/// 運行開始の盤。端末外形 390×844 を、入った領域へ縦横同じ倍率で収める。
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
        @ViewBuilder departChevrons: () -> some View = { EmptyView() },
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
            let scale = fitted.width / OpeningPanelTokens.Phone.width
            designPhone
                .frame(
                    width: OpeningPanelTokens.Phone.width,
                    height: OpeningPanelTokens.Phone.height
                )
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: fitted.width, height: fitted.height, alignment: .topLeading)
                .clipped()
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("運行開始の盤")
    }

    private var designPhone: some View {
        Color.clear
            .frame(
                width: OpeningPanelTokens.Phone.width,
                height: OpeningPanelTokens.Phone.height
            )
            .overlay(alignment: .topLeading) {
                lattice
                    .padding(.top, OpeningPanelTokens.Phone.gridOrigin.y)
                    .padding(.leading, OpeningPanelTokens.Phone.gridOrigin.x)
            }
            .background {
                RoundedRectangle(cornerRadius: OpeningPanelTokens.Phone.radius, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.housing)
            }
        .clipShape(RoundedRectangle(cornerRadius: OpeningPanelTokens.Phone.radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OpeningPanelTokens.Phone.radius, style: .continuous)
                .strokeBorder(OpeningPanelTokens.Palette.phoneBorder, lineWidth: OpeningPanelTokens.Phone.border)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }

    private var lattice: some View {
        OpeningPanelLattice {
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
            OpeningPanelModule(tone: .standard, alignment: .center) {
                OpeningPanelCenterRow {
                    HStack(spacing: 4) {
                        OpeningPanelLegend(
                            text: "CHK",
                            size: 7,
                            tracking: 0.14,
                            padding: EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3)
                        )
                        lampPair("MSTR")
                        lampPair("CLK")
                        lampPair("TT")
                        lampPair("TKT")
                        check
                    }
                    .padding(.horizontal, 5)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("CHK")

            OpeningPanelModule(tone: .standard, alignment: .center) {
                OpeningPanelCenterRow {
                    HStack(spacing: 4) {
                        OpeningPanelLegend(
                            text: "PHONE",
                            size: 7,
                            tracking: 0.14,
                            padding: EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3)
                        )
                        OpeningPanelWindow { phone }
                            .frame(width: 36, height: OpeningPanelTokens.Chrome.phoneWindowHeight)
                        lampPair("EXT")
                        lampPair("AWAKE")
                    }
                    .padding(.horizontal, 5)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("PHONE")
        }
    }

    private func lampPair(_ name: String) -> some View {
        HStack(spacing: 2) {
            OpeningPanelLamp()
            Text(name)
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.14)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)
                .lineLimit(1)
        }
    }

    private var masterModule: some View {
        OpeningPanelModule(tone: .upper) {
            master
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MASTER")
    }

    private var clockModule: some View {
        OpeningPanelModule(tone: .upper) {
            OpeningPanelWindow(exposesContent: true) { clock }
                .padding(6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("時計")
    }

    private var clockKeyModule: some View {
        OpeningPanelModule(tone: .upper) {
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
        HStack(spacing: 6) {
            OpeningPanelLegend(text: "TIMETABLE")
            timetableTitle
            ZStack {
                OpeningPanelScaleToggle()
                scaleToggle
            }
            OpeningPanelWindow { range }
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
            OpeningPanelWindow { timetable }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            OpeningPanelWindow(label: "運転状況") { runStatus }
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
        OpeningPanelModule(tone: .standard) {
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
        OpeningPanelModule(tone: .lower) {
            VStack(spacing: 5) {
                HStack(spacing: 8) {
                    OpeningPanelLegend(text: "TICKETS")
                    Spacer(minLength: 0)
                    ZStack {
                        OpeningPanelSeqKey()
                        sequenceKey
                    }
                    .frame(width: 36, height: 20)
                    ZStack {
                        OpeningPanelConfirmKey()
                        ticketsKey
                    }
                    .frame(width: 64, height: 30)
                }
                .frame(height: 30)
                HStack(alignment: .top, spacing: 4) {
                    OpeningPanelSlotNames()
                    ticketsLeading
                    OpeningPanelTodayMark()
                    OpeningPanelTodayRail()
                        .padding(.leading, -2)
                    OpeningPanelWindow { tickets }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .padding(6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TICKETS")
    }

    private var loadModule: some View {
        OpeningPanelModule(tone: .standard) {
            VStack(alignment: .leading, spacing: 4) {
                OpeningPanelLegend(text: "LOAD")
                ZStack {
                    OpeningPanelLoadFace()
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
        OpeningPanelModule(tone: .standard) {
            HStack(spacing: 4) {
                OpeningPanelLegend(
                    text: "COMM",
                    size: 7,
                    tracking: 0.14,
                    padding: EdgeInsets(top: 1, leading: 3, bottom: 1, trailing: 3),
                    strip: OpeningPanelTokens.Palette.commStrip
                )
                ZStack {
                    OpeningPanelCap(side: 16)
                    commTest
                }
                .frame(width: 16, height: 16)
                Text("TEST")
                    .font(OpeningPanelFaceFont.legend(7))
                    .tracking(0.14)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                    .lineLimit(1)
                OpeningPanelWindow { comm }
                    .frame(height: OpeningPanelTokens.Chrome.commWindowHeight)
                lampPair("RELAY")
                lampPair("MAC")
            }
            .padding(.horizontal, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("COMM")
    }

    private var departModule: some View {
        OpeningPanelModule(tone: .lower) {
            HStack(alignment: .center, spacing: 6) {
                VStack(spacing: 3) {
                    ZStack {
                        OpeningPanelLockRow()
                        departLock
                    }
                    .frame(height: 11)
                    OpeningPanelWindow { departStatus }
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                    OpeningPanelWindow { departFirst }
                        .frame(height: OpeningPanelTokens.Chrome.departLineHeight)
                    OpeningPanelChevronWell()
                        .frame(height: OpeningPanelTokens.Chrome.chevronWellHeight)
                        .overlay { departChevrons }
                }
                .frame(width: OpeningPanelTokens.Chrome.departReadoutWidth, alignment: .top)
                OpeningPanelPushBar {
                    ZStack {
                        OpeningPanelDepartLabel()
                            .accessibilityHidden(true)
                        departBar
                    }
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
    private var content: Content

    init(
        tone: OpeningPanelTokens.FaceTone,
        alignment: Alignment = .top,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
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
            chrome.accessibilityElement(children: .contain)
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
    private var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
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
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(OpeningPanelTokens.Palette.barRingMid, lineWidth: 2)
                    .padding(-3)
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
