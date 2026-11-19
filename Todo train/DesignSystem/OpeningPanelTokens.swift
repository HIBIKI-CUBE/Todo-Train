//
//  OpeningPanelTokens.swift
//  Todo train
//
//  運行開始の盤の格子・色・字の大きさ・間。
//  赤は置かない。故障の黄は #f0c000。
//

import SwiftUI

enum OpeningPanelTokens {
    /// 格子の外枠 372×782。枠線 2 の内側が 368×778。
    ///
    /// 列 `118 / 1fr / 86`、行 `22 / 100 / 1fr / 50 / 150 / 22 / 92`、間隔 2。
    /// モジュールは枠の内側 (2, 2) から始まり、右端と下端は 370 と 780 に揃う。
    /// 可変の列は 160、可変の行は 330。画面に合わせてこの箱ごと拡縮し、中の列は伸ばさない。
    enum Canvas {
        static let width: CGFloat = 372
        static let height: CGFloat = 782
        static let border: CGFloat = 2
        static var outer: CGSize { CGSize(width: width, height: height) }
    }

    /// モックの端末外形。余白は上 44、左右 8、下 16。枠線 1 を含めて格子が (9, 45) に乗る。
    enum Phone {
        static let width: CGFloat = 390
        static let height: CGFloat = 844
        static let radius: CGFloat = 44
        static let border: CGFloat = 1
        static let paddingTop: CGFloat = 44
        static let paddingSide: CGFloat = 8
        static let paddingBottom: CGFloat = 16
        static var gridOrigin: CGPoint {
            CGPoint(x: border + paddingSide, y: border + paddingTop)
        }
        static var size: CGSize { CGSize(width: width, height: height) }
    }

    enum Track: Equatable {
        case fixed(CGFloat)
        case flexible
    }

    enum Grid {
        static let columns: [Track] = [.fixed(118), .flexible, .fixed(86)]
        static let rows: [Track] = [
            .fixed(22), .fixed(100), .flexible,
            .fixed(50), .fixed(150), .fixed(22), .fixed(92)
        ]
        static let gap: CGFloat = 2
        /// 座標表の最初のモジュールの位置。トラックはここから右端・下端まで埋める。
        static let origin: CGFloat = 2

        static func lengths(_ tracks: [Track], span: CGFloat, gap: CGFloat = Grid.gap) -> [CGFloat] {
            let gapTotal = gap * CGFloat(max(0, tracks.count - 1))
            let fixed = tracks.reduce(CGFloat(0)) { sum, track in
                if case .fixed(let length) = track { return sum + length }
                return sum
            }
            let flexibleCount = tracks.reduce(0) { count, track in
                if case .flexible = track { return count + 1 }
                return count
            }
            let flexible = flexibleCount > 0
                ? (span - gapTotal - fixed) / CGFloat(flexibleCount)
                : 0
            return tracks.map { track in
                switch track {
                case .fixed(let length):
                    return length
                case .flexible:
                    return flexible
                }
            }
        }

        static func origins(_ lengths: [CGFloat], gap: CGFloat = Grid.gap) -> [CGFloat] {
            var cursor: CGFloat = 0
            return lengths.map { length in
                let origin = cursor
                cursor += length + gap
                return origin
            }
        }
    }

    enum FaceTone {
        /// 地のモジュール。
        case standard
        /// MASTER・時計・CLOCK。モックの一段明るい面。
        case upper
        /// TICKETS・DEPART。モックの一段暗い面。
        case lower

        var fill: Color {
            switch self {
            case .standard:
                return Palette.module
            case .upper:
                return Palette.moduleUpper
            case .lower:
                return Palette.moduleLower
            }
        }
    }

    enum Module: String, CaseIterable {
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

        var columns: ClosedRange<Int> {
            switch self {
            case .master:
                return 0...0
            case .clock:
                return 1...1
            case .clockKey, .load:
                return 2...2
            case .tickets:
                return 0...1
            case .sysbar, .timetable, .nowBoard, .comm, .depart:
                return 0...2
            }
        }

        var row: Int {
            switch self {
            case .sysbar:
                return 0
            case .master, .clock, .clockKey:
                return 1
            case .timetable:
                return 2
            case .nowBoard:
                return 3
            case .tickets, .load:
                return 4
            case .comm:
                return 5
            case .depart:
                return 6
            }
        }

        var tone: FaceTone {
            switch self {
            case .master, .clock, .clockKey:
                return .upper
            case .tickets, .depart:
                return .lower
            case .sysbar, .timetable, .nowBoard, .load, .comm:
                return .standard
            }
        }

        /// 設計寸法の格子の中の外形。原点は格子の外枠の左上。
        func frame() -> CGRect {
            let columnLengths = Grid.lengths(Grid.columns, span: Canvas.width - Canvas.border * 2)
            let rowLengths = Grid.lengths(Grid.rows, span: Canvas.height - Canvas.border * 2)
            let columnOrigins = Grid.origins(columnLengths).map { $0 + Canvas.border }
            let rowOrigins = Grid.origins(rowLengths).map { $0 + Canvas.border }
            let start = columns.lowerBound
            let end = columns.upperBound
            let x = columnOrigins[start]
            let y = rowOrigins[row]
            let width = columnOrigins[end] + columnLengths[end] - x
            let height = rowLengths[row]
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    /// 運転状況の列と、時間割の窓の内側。上下は同じ 3。左右 4 は列だけ。
    enum RunStatus {
        static let width: CGFloat = 84
        /// 時間割の窓とこの列の間。モックの `.ttRow` は 4。格子の間隔とは別。
        static let columnGap: CGFloat = 4
        static let verticalInset: CGFloat = 3
        static let horizontalInset: CGFloat = 4
    }

    struct TimetableSplit: Equatable {
        var timetableWindow: CGRect
        var runStatusWindow: CGRect
        var timetableContent: CGRect
        var runStatusContent: CGRect
    }

    /// 時間割の行の中で、二つの窓の内側の上端・下端をそろえる。
    static func timetableSplit(in row: CGRect) -> TimetableSplit {
        let statusWidth = min(RunStatus.width, max(0, row.width))
        let timetableWidth = max(0, row.width - RunStatus.columnGap - statusWidth)
        let timetableWindow = CGRect(
            x: row.minX,
            y: row.minY,
            width: timetableWidth,
            height: row.height
        )
        let runStatusWindow = CGRect(
            x: row.minX + timetableWidth + RunStatus.columnGap,
            y: row.minY,
            width: statusWidth,
            height: row.height
        )
        return TimetableSplit(
            timetableWindow: timetableWindow,
            runStatusWindow: runStatusWindow,
            timetableContent: inset(
                timetableWindow,
                top: RunStatus.verticalInset,
                leading: 0,
                bottom: RunStatus.verticalInset,
                trailing: 0
            ),
            runStatusContent: inset(
                runStatusWindow,
                top: RunStatus.verticalInset,
                leading: RunStatus.horizontalInset,
                bottom: RunStatus.verticalInset,
                trailing: RunStatus.horizontalInset
            )
        )
    }

    /// 空の外枠に使う寸法。割り付けの表と、モックの操作面。
    enum Chrome {
        static let modulePadding: CGFloat = 6
        static let windowRadius: CGFloat = 1
        static let controlRadius: CGFloat = 2
        static let controlPadding: CGFloat = 3
        static let controlLip: CGFloat = 2
        static let hairline: CGFloat = 0.5
        /// CHK と PHONE の間。仕様は sysbar を一つの行にし、この分割はモックの帯。
        static let stripSplit: CGFloat = 2
        static let phoneWindowHeight: CGFloat = 16
        static let commWindowHeight: CGFloat = 16
        /// COMM の押しボタンと窓の間。モックは 6。
        static let commSpacing: CGFloat = 6
        static let clockKeySize = CGSize(width: 56, height: 40)
        static let hourModeSize = CGSize(width: 18, height: 18)
        static let testSize = CGSize(width: 16, height: 16)
        static let scaleToggleSize = CGSize(width: 12, height: 22)
        static let timetableKeySize = CGSize(width: 52, height: 30)
        static let sequenceKeySize = CGSize(width: 36, height: 20)
        static let ticketsKeySize = CGSize(width: 64, height: 30)
        static let rangeWindow = CGSize(width: 60, height: 16)
        static let nextWindow = CGSize(width: 44, height: 13)
        static let nowWindow = CGSize(width: 304, height: 38)
        static let ticketsWindow = CGSize(width: 200, height: 103)
        static let loadGauge = CGSize(width: 40, height: 120)
        static let departReadoutWidth: CGFloat = 214
        static let departBar = CGSize(width: 132, height: 82)
        static let departGap: CGFloat = 6
        static let departPaddingH: CGFloat = 9
        static let departPaddingV: CGFloat = 5
        static let departLineHeight: CGFloat = 16
        static let chevronCount = 10
        /// 出発モジュールの内側 82 から、錠の行と窓 2 本と間隔を引いた残り。
        static let chevronWellHeight: CGFloat = 30
        /// 次に自動で始まるキーの縁。
        static let nextKeyEdge: CGFloat = 1
    }

    /// ただいま板と DEPART 横の行。仕様の字の大きさ。
    enum TypeSize {
        static let nowStatus: CGFloat = 17
        static let nowPrimary: CGFloat = 24
        static let nowSecondary: CGFloat = 17
        static let caption: CGFloat = 10
        static let departLine: CGFloat = 10
    }

    /// 運転状況の塗り・参照帯の強調。赤は置かない。
    enum RunStatusChrome {
        static let nowChipSize = CGSize(width: 16, height: 22)
        static let departChipSize = CGSize(width: 10, height: 8)
        static let referenceBarWidth: CGFloat = 3
        static let pastBandOpacity: CGFloat = 0.38
        static let referencedBandFill = color(0xFFB000, opacity: 0.34)
        static let referenceAccent = color(0xFFCF5A)
        static let holdFace = color(0x121314)
        static let holdEdge = color(0xF2E6C8, opacity: 0.4)
        static let preEdge = color(0xF2E6C8, opacity: 0.35)
        static let denseStripe = color(0xFFB000, opacity: 0.7)
        static let denseStripeBackground = Color.clear
        static let brightBandStroke = color(0xF2E6C8, opacity: 0.55)
    }

    /// 縦の時間割と、運転状況の列の塗り。赤は置かない。
    enum TimetableChrome {
        static let amberSolid = color(0xFFB000)
        static let adoptedBand = color(0xFFB000, opacity: 0.60)
        static let passingEdge = color(0xFFB000, opacity: 0.55)
        static let nowBand = color(0xFFB000, opacity: 0.07)
        static let nowBandEdge = color(0xFFB000, opacity: 0.45)
        static let nowBandHatch = color(0xFFB000, opacity: 0.16)
        static let leader = color(0xFFB000, opacity: 0.60)
        static let hourLine = color(0xFFB000, opacity: 0.20)
        static let hourLabel = color(0xFFB000, opacity: 0.60)
        static let rowTime = color(0xFFB000, opacity: 0.75)
        static let nextIdle = color(0xFFB000, opacity: 0.30)
        static let fill = color(0xFFB000, opacity: 0.60)
        static let markInk = color(0x151617)
        static let overviewTrack = color(0xF0EBDA, opacity: 0.84)
        static let normalFace = color(0xFFB000, opacity: 0.16)
        static let denseFace = color(0xFFB000, opacity: 0.06)
        static let denseHatch = color(0xFFB000, opacity: 0.34)
        static let holdName = color(0xF2E6C8, opacity: 0.60)
        static let denseName = color(0xFFCF5A)
        static let rowLine = color(0x222222)
    }

    /// 仕様「間」。テンポの付いた項目は `tempo` を一度だけ掛ける。
    enum Interval {
        static let lampCheck: TimeInterval = 0.280
        static let autoWait: TimeInterval = 0.800
        static let autoStep: TimeInterval = 0.120
        static let backlightDelay: TimeInterval = 0.050
        /// 70ms × 0.6。テンポは未適用。
        static let powerLEDStep: TimeInterval = 0.070 * 0.6
        static let powerConfirmed: TimeInterval = 0.150
        static let clockDigit: TimeInterval = 0.110
        static let clockBeforeLive: TimeInterval = 0.300
        static let timetableFill: TimeInterval = 0.032
        static let timetableBeforeTest: TimeInterval = 0.150
        static let timetableDraw: TimeInterval = 0.300
        static let ticketsCursor: TimeInterval = 0.070
        static let ticketsAfterCursor: TimeInterval = 0.150
        static let ticketsCard: TimeInterval = 0.110
        static let checkBlink: TimeInterval = 0.060
        static let tempoPercent: Double = 170

        static func tempo(_ base: TimeInterval) -> TimeInterval {
            base * 100 / tempoPercent
        }
    }

    /// モックの atmos 面。金属や木目は使わず、平面の縁と影だけ。
    enum Palette {
        static let housing = color(0x404245)
        static let grid = color(0x44474A)
        static let module = color(0x5F6265)
        static let moduleUpper = color(0x66696C)
        static let moduleLower = color(0x585B5E)
        static let moduleEdgeInner = color(0x535659)
        static let moduleEdgeOuter = color(0x36383A)
        static let window = color(0x1A1B1C)
        static let windowEdge = Color.black.opacity(0.3)
        static let strip = color(0x45484B)
        static let legend = color(0xF0EBDA, opacity: 0.84)
        /// `--leg`。フィルタの外にある DEPART の刻印。
        static let engraved = color(0xF2E6C8, opacity: 0.72)
        /// `.k` に brightness(1.16) を掛けた面と、その下の唇。
        static let raised = color(0x2E3033, brightness: 1.16)
        static let raisedLip = color(0x1D1E20)
        static let lens = color(0x5A5D60, brightness: 1.16)
        static let cap = color(0x1D1E1F, brightness: 1.16)
        static let capLip = color(0x0E0F10, brightness: 1.16)
        static let capRing = color(0x4A4E52, brightness: 1.16)
        static let capRingOuter = color(0x2E3033, brightness: 1.16)
        static let barHousing = color(0x141516)
        static let barRing = color(0x75797D)
        static let barRingMid = color(0x4A4D51)
        static let barRingInner = color(0x1F2022)
        static let barFace = color(0x5B5E61)
        static let barHighlight = color(0x75797C)
        static let barShade = color(0x3B3E41)
        static let barLip = color(0x0C0C0D)
        static let chevron = color(0x2B2C2E)
        static let chevronWell = color(0x1A1B1C)
        static let lampOff = color(0x2A2B2C)
        static let commStrip = color(0x34373A)
        static let phoneBorder = color(0x222222)
        static let segInk = color(0xF2E6C8, opacity: 0.4)
        static let lockInk = color(0xF2E6C8, opacity: 0.5)
        static let gaugeHairline = color(0xF2E6C8, opacity: 0.15)
        /// 灯った LOAD の枠。`.gbox` の `rgba(242,230,200,.5)`。
        static let gaugeFrame = color(0xF2E6C8, opacity: 0.5)
        /// 空きに収まる面。`.gIn`。
        static let gaugeFit = color(0xF2E6C8, opacity: 0.55)
        static let railTick = color(0xF2E6C8, opacity: 0.22)
        static let amber = color(0xFFB000, opacity: 0.85)
        static let amberDim = color(0xFFB000, opacity: 0.14)
        /// 確認灯。盤の CHK は緑で点いてよい。
        static let lampGreen = color(0x84C480, opacity: 0.85)
        static let lampGreenWell = color(0x1E3320)
        /// 故障の黄。`#f0c000`。
        static let fault = color(0xF0C000)
        /// 次に自動で始まるキーの縁。`rgba(242,230,200,.3)`。
        static let nextKeyEdge = color(0xF2E6C8, opacity: 0.3)
        /// `.pre` は `.k` の上にあり、最終的に `brightness(1.16)` が乗る。
        static var keyNextEdge: Color {
            color(0xF2E6C8, brightness: 1.16, opacity: 0.3)
        }

        /// `.k` と `.cap` の `brightness(1.16)`。色を掛けてから描く。
        static func key(_ hex: UInt32, opacity: Double = 1) -> Color {
            color(hex, brightness: 1.16, opacity: opacity)
        }

        static func hex(_ value: UInt32, opacity: Double = 1) -> Color {
            color(value, opacity: opacity)
        }

        /// `--leg` を `brightness(1.16)` した面。文字はこれに 0.72 を掛ける。
        static var keyLegendInk: Color {
            color(0xF2E6C8, brightness: 1.16)
        }

        /// 目盛り。色の不透明度がそのまま乗る。
        static var keyLegend: Color {
            color(0xF2E6C8, brightness: 1.16, opacity: 0.72)
        }

        static var keySegInk: Color {
            Color(red: 1, green: 1, blue: min(1, 200 / 255 * 1.16), opacity: 0.4)
        }

        static var keyCyan: Color {
            Color(
                red: min(1, 120 / 255 * 1.16),
                green: min(1, 190 / 255 * 1.16),
                blue: min(1, 200 / 255 * 1.16),
                opacity: 0.8
            )
        }

        static var keyGreenInk: Color {
            Color(
                red: min(1, 132 / 255 * 1.16),
                green: min(1, 196 / 255 * 1.16),
                blue: min(1, 128 / 255 * 1.16),
                opacity: 0.85
            )
        }
    }
}

enum OpeningPanelFaceFont {
    static func legend(_ size: CGFloat) -> Font {
        Font.custom("Helvetica Neue", size: size).weight(.medium)
    }
}

private func color(_ hex: UInt32, brightness: Double = 1, opacity: Double = 1) -> Color {
    func channel(_ shift: UInt32) -> Double {
        let value = Double((hex >> shift) & 0xFF) / 255 * brightness
        return min(max(value, 0), 1)
    }
    return Color(red: channel(16), green: channel(8), blue: channel(0), opacity: opacity)
}

private func inset(
    _ rect: CGRect,
    top: CGFloat,
    leading: CGFloat,
    bottom: CGFloat,
    trailing: CGFloat
) -> CGRect {
    CGRect(
        x: rect.minX + leading,
        y: rect.minY + top,
        width: max(0, rect.width - leading - trailing),
        height: max(0, rect.height - top - bottom)
    )
}
