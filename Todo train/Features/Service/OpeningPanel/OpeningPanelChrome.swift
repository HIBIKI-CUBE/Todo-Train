//
//  OpeningPanelChrome.swift
//  Todo train
//
//  盤の地。電源オフの刻印・窓・灯・キー・レール。中身は窓へ差し込む。
//

import SwiftUI

struct OpeningPanelLegend: View {
    var text: String
    var size: CGFloat = 8
    var tracking: CGFloat?
    var color: Color = OpeningPanelTokens.Palette.legend
    var padding = EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4)
    var strip: Color? = OpeningPanelTokens.Palette.strip

    var body: some View {
        Text(text)
            .font(OpeningPanelFaceFont.legend(size))
            .tracking(tracking ?? size * 0.05)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(padding)
            .background {
                if let strip {
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(strip)
                }
            }
    }
}

struct OpeningPanelLamp: View {
    var diameter: CGFloat = 6

    var body: some View {
        Circle()
            .fill(OpeningPanelTokens.Palette.lampOff)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// STBY / OK の確認キー。唇は枠の外へ 2。
struct OpeningPanelConfirmKey: View {
    var top: String = "STBY"
    var bottom: String = "OK"
    var topSize: CGFloat = 7
    var bottomSize: CGFloat = 8
    var topAvailable = false
    var bottomLit = false

    private typealias Palette = OpeningPanelTokens.Palette

    var body: some View {
        lens
            .padding(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.key(0x2E3033))
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.key(0x1D1E20))
                    .frame(height: 2)
                    .offset(y: 2)
            }
    }

    private var lens: some View {
        VStack(spacing: 0) {
            Text(top)
                .font(OpeningPanelFaceFont.legend(topSize))
                .tracking(topSize * 0.08)
                .foregroundStyle(topAvailable ? Palette.keyCyan : Palette.keySegInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(topAvailable ? Palette.key(0x1D2F33) : Palette.key(0x5A5D60))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Palette.key(0x45484B))
                        .frame(height: 1)
                }
            Text(bottom)
                .font(OpeningPanelFaceFont.legend(bottomSize))
                .tracking(bottomSize * 0.08)
                .foregroundStyle(bottomLit ? Palette.keyGreenInk : Palette.keySegInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(bottomLit ? Palette.key(0x1E3320) : Palette.key(0x5A5D60))
        }
        .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 0, y: 1)
    }
}

struct OpeningPanelSeqKey: View {
    var body: some View {
        Text("SEQ")
            .font(OpeningPanelFaceFont.legend(9))
            .tracking(9 * 0.15)
            .foregroundStyle(OpeningPanelTokens.Palette.keySegInk)
            .shadow(color: .black.opacity(0.45), radius: 0, y: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OpeningPanelTokens.Palette.key(0x2F3133))
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

/// 12/24 と TEST の角キャップ。輪は枠の外へ 3、唇は下へ 2。
struct OpeningPanelCap: View {
    var side: CGFloat = 18

    private typealias Palette = OpeningPanelTokens.Palette

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Palette.key(0x1D1E1F))
            .frame(width: side, height: side)
            .background {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Palette.key(0x4A4E52))
                    .frame(width: side + 2, height: side + 2)
            }
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.key(0x2E3033))
                    .frame(width: side + 6, height: side + 6)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.key(0x0E0F10))
                    .frame(width: side, height: 2)
                    .offset(y: 2)
            }
            .frame(width: side, height: side)
    }
}

struct OpeningPanelScaleToggle: View {
    var twentyFour = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.hex(0x2E3033))
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.hex(0x1D1E20))
                    .frame(height: 1)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.hex(0x8A8E92))
                    .frame(width: 6, height: 9)
                    .offset(x: 3, y: twentyFour ? 11 : 2)
            }
            .frame(width: 12, height: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text("AUTO")
                    .frame(height: 10, alignment: .leading)
                Text("24H")
                    .frame(height: 10, alignment: .leading)
            }
            .font(OpeningPanelFaceFont.legend(8))
            .tracking(0.4)
            .foregroundStyle(OpeningPanelTokens.Palette.legend)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(twentyFour ? "24時間" : "自動")
    }
}

struct OpeningPanelTodayRail: View {
    var rows = 5
    var cutAfter = 3

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(OpeningPanelTokens.Palette.hex(0x1C1D1F))
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(OpeningPanelTokens.Palette.hex(0x0D0D0E))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(OpeningPanelTokens.Palette.hex(0x0D0D0E))
                        .frame(height: 1)
                }
            ForEach(0...rows, id: \.self) { index in
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.railTick)
                    .frame(height: 1)
                    .padding(.horizontal, 2)
                    .offset(y: 2 + CGFloat(index) * 21)
            }
            knob
                .offset(x: 1, y: 2 + CGFloat(cutAfter) * 21 - 6)
        }
        .frame(width: 16)
        .accessibilityHidden(true)
    }

    private var knob: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(OpeningPanelTokens.Palette.hex(0x85898D))
            VStack {
                Spacer(minLength: 0)
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.hex(0x5C6064))
                    .frame(height: 2)
            }
            UnevenRoundedRectangle(bottomLeadingRadius: 3)
                .fill(OpeningPanelTokens.Palette.hex(0x2A2B2D))
                .frame(width: 6, height: 5)
                .offset(x: 6, y: 3)
            Rectangle()
                .fill(OpeningPanelTokens.Palette.hex(0x3A3C3F))
                .frame(width: 3, height: 2)
                .offset(x: 2, y: 5)
        }
        .frame(width: 14, height: 12)
        .shadow(color: OpeningPanelTokens.Palette.hex(0x0E0F10), radius: 0, y: 1)
    }
}

struct OpeningPanelLoadFace: View {
    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            OpeningPanelWindow {
                Color.clear
            }
            .frame(width: 40)
            .overlay { gaugeBox }
            freeMark
                .frame(width: 26)
        }
        .accessibilityHidden(true)
    }

    private var gaugeBox: some View {
        GeometryReader { geo in
            let top = geo.size.height * 0.36
            let bottom = max(0, geo.size.height * 0.04 - 2)
            Rectangle()
                .strokeBorder(OpeningPanelTokens.Palette.gaugeHairline, lineWidth: 1)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(OpeningPanelTokens.Palette.gaugeHairline)
                        .frame(height: 2)
                }
                .padding(EdgeInsets(top: top, leading: 6, bottom: bottom, trailing: 6))
        }
        .allowsHitTesting(false)
    }

    private var freeMark: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.legend)
                    .frame(width: 4, height: 1)
                Text("FREE")
                    .font(OpeningPanelFaceFont.legend(8))
                    .tracking(0.4)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                    .fixedSize()
            }
            .position(x: 18, y: geo.size.height * 0.36)
        }
    }
}

struct OpeningPanelSlotNames: View {
    private let names = ["先発", "次発", "次々発", "4", "5"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(OpeningPanelFaceFont.legend(8))
                    .tracking(0.4)
                    .foregroundStyle(OpeningPanelTokens.Palette.legend)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .frame(height: 21)
            }
        }
        .padding(.top, 2)
        .frame(width: 34, alignment: .top)
    }
}

struct OpeningPanelTodayMark: View {
    var body: some View {
        Text("TODAY")
            .font(OpeningPanelFaceFont.legend(7))
            .tracking(7 * 0.2)
            .foregroundStyle(OpeningPanelTokens.Palette.legend)
            .fixedSize()
            .rotationEffect(.degrees(90))
            .frame(width: 8)
            .padding(.top, 4)
            .accessibilityLabel("TODAY")
    }
}

struct OpeningPanelChevronWell: View {
    var body: some View {
        OpeningPanelChevronRow()
            .padding(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.chevronWell)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.hex(0x0C0C0D))
                    .frame(height: 1)
            }
    }
}

struct OpeningPanelDepartLabel: View {
    var sunk = false

    var body: some View {
        Text("出 発")
            .font(.system(size: 15, weight: .semibold))
            .tracking(9)
            .padding(.leading, 9)
            .foregroundStyle(sunk ? OpeningPanelTokens.Palette.keyGreenInk : OpeningPanelTokens.Palette.segInk)
            .shadow(color: .black.opacity(0.45), radius: 0, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(sunk ? OpeningPanelTokens.Palette.hex(0x1F3121) : OpeningPanelTokens.Palette.barFace)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.barHighlight)
                    .frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(OpeningPanelTokens.Palette.barShade)
                    .frame(height: 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
    }
}

/// MASTER のキー、レンズ、PWR。モジュールの余白込み。
struct OpeningPanelMasterAssembly: View {
    var powered = false
    var keyDegrees: Double = -45
    var litLEDCount: Int = 0
    var standbyAvailable = true
    var onPress: () -> Void = {}

    private typealias Palette = OpeningPanelTokens.Palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            OpeningPanelLegend(text: "MASTER")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onPress) {
                HStack(alignment: .center, spacing: 6) {
                    keyHead
                        .frame(width: 58, height: 60)
                    lens
                        .frame(width: 46, height: 46)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(powered ? "MASTER ON" : "MASTER OFF")
            .accessibilityHint("運行の電源を入れます")
            powerRow
        }
        .padding(EdgeInsets(top: 8, leading: 7, bottom: 6, trailing: 7))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyHead: some View {
        ZStack(alignment: .topLeading) {
            Text("OFF")
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.35)
                .foregroundStyle(Palette.keyLegend)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text("ON")
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.35)
                .foregroundStyle(Palette.keyLegend)
                .padding(.trailing, 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            tick(degrees: -45)
                .position(x: 12.5, y: 13.5)
            tick(degrees: 45)
                .position(x: 45.5, y: 13.5)
            well
                .position(x: 29, y: 35)
        }
    }

    private func tick(degrees: Double) -> some View {
        Rectangle()
            .fill(Palette.keyLegend)
            .frame(width: 1, height: 5)
            .rotationEffect(.degrees(degrees))
    }

    private var well: some View {
        ZStack {
            Circle()
                .fill(Palette.key(0x232426))
                .frame(width: 52, height: 52)
            Circle()
                .fill(Palette.key(0x5D6165))
                .frame(width: 46, height: 46)
            Circle()
                .fill(Palette.key(0x1A1B1C))
                .frame(width: 42, height: 42)
            blade
                .rotationEffect(.degrees(keyDegrees))
        }
        .frame(width: 52, height: 52)
    }

    private var blade: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Palette.key(0x8B8F93))
            .frame(width: 12, height: 34)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Palette.key(0x5F6367))
                    .frame(width: 1)
            }
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(Palette.key(0x3A3C3F))
                    .frame(width: 2, height: 8)
                    .offset(x: 5, y: 3)
            }
            .shadow(color: Palette.key(0x0E0E0F), radius: 0, y: 1)
    }

    private var lens: some View {
        let available = standbyAvailable && !powered
        return VStack(spacing: 0) {
            Text("STBY")
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.56)
                .foregroundStyle(available ? Palette.keyCyan : Palette.keySegInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(available ? Palette.key(0x1D2F33) : Palette.key(0x55585B))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Palette.key(0x45484B))
                        .frame(height: 1)
                }
            Text("ON")
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.56)
                .foregroundStyle(powered ? Palette.keyGreenInk : Palette.keySegInk)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(powered ? Palette.key(0x1E3320) : Palette.key(0x55585B))
        }
        .frame(width: 40, height: 40)
        .padding(3)
        .background(Palette.key(0x2E3033))
    }

    private var powerRow: some View {
        HStack(spacing: 5) {
            Text("PWR")
                .font(OpeningPanelFaceFont.legend(8))
                .tracking(0.4)
                .foregroundStyle(Palette.legend)
            HStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { index in
                    Rectangle()
                        .fill(ledColor(index))
                        .frame(height: 9)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PWR \(powered ? litLEDCount : 0) / 6")
    }

    private func ledColor(_ index: Int) -> Color {
        guard powered else { return Palette.lampOff }
        return index < litLEDCount ? Palette.amber : Palette.amberDim
    }
}

struct OpeningPanelLockRow: View {
    var body: some View {
        HStack(spacing: 3) {
            lock("MSTR")
            lock("CLK")
            lock("TT")
            lock("TKT")
            Spacer(minLength: 0)
            OpeningPanelLamp()
            Text("READY")
                .font(OpeningPanelFaceFont.legend(7))
                .tracking(0.35)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)
                .lineLimit(1)
        }
        .frame(height: 11)
    }

    private func lock(_ name: String) -> some View {
        HStack(spacing: 3) {
            Rectangle()
                .fill(OpeningPanelTokens.Palette.lampOff)
                .frame(width: 9, height: 3)
            Text(name)
                .font(OpeningPanelFaceFont.legend(6))
                .tracking(0.3)
                .foregroundStyle(OpeningPanelTokens.Palette.lockInk)
                .lineLimit(1)
        }
        .padding(.trailing, 3)
    }
}

struct OpeningPanelNextPair: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            nextRow("NEXT STOP IN")
            nextRow("NEXT RIDE IN")
        }
    }

    private func nextRow(_ title: String) -> some View {
        HStack(spacing: 5) {
            OpeningPanelLamp()
            Text(title)
                .font(OpeningPanelFaceFont.legend(8))
                .tracking(0.4)
                .foregroundStyle(OpeningPanelTokens.Palette.legend)
                .opacity(0.42)
                .lineLimit(1)
            OpeningPanelWindow { Color.clear }
                .frame(width: 44, height: 13)
        }
    }
}
