//
//  ServiceCabinChrome.swift
//  Todo train
//
//  運行の機体: 表示灯・TIMS井戸・黒ガラスの括弧枠。
//  燐光緑が主。マスコン・社名・英語の起動コピーは借りない。
//

import SwiftUI

struct ServiceCabinCanopy: View {
    var lamp: ServiceCabinLamp
    var poweringDown: Bool = false
    var sweepTick: Int = 0
    var reduceTransparency: Bool = false

    var body: some View {
        ZStack {
            Color.black
            if !reduceTransparency {
                RadialGradient(
                    colors: [
                        LEDPhosphor.on.opacity(glow),
                        Color.clear
                    ],
                    center: UnitPoint(x: 0.5, y: 1.08),
                    startRadius: 8,
                    endRadius: 560
                )
                RadialGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(lamp == .dark ? 0.82 : 0.46)
                    ],
                    center: .center,
                    startRadius: 40,
                    endRadius: 480
                )
                ServiceCabinScanlines()
                    .opacity(lamp == .dark ? 0.18 : 0.32)
            }
            ServiceCabinSweep(tick: sweepTick)
                .opacity(poweringDown ? 0 : 1)
        }
        .ignoresSafeArea()
        .opacity(poweringDown && lamp == .dark ? 0.2 : 1)
        .animation(.easeInOut(duration: 0.55), value: lamp)
    }

    private var glow: Double {
        if poweringDown { return lamp >= .lamp ? 0.05 : 0 }
        switch lamp {
        case .dark: return 0
        case .lamp: return 0.07
        case .occupancy: return 0.11
        case .phosphor, .boardReady: return 0.16
        case .circuits: return 0.20
        }
    }
}

struct ServiceCabinScanlines: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(Color.black.opacity(0.28)), lineWidth: 1)
                y += 3
            }
        }
        .allowsHitTesting(false)
        .blendMode(.multiply)
    }
}

struct ServiceCabinSweep: View {
    var tick: Int
    @State private var travel: CGFloat = -0.08

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.clear,
                    LEDPhosphor.on.opacity(0.0),
                    LEDPhosphor.on.opacity(0.55),
                    LEDPhosphor.on.opacity(0.0),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 36)
            .offset(y: geo.size.height * travel)
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onChange(of: tick) { _, _ in
            travel = -0.08
            withAnimation(.easeIn(duration: 0.72)) {
                travel = 1.08
            }
        }
    }
}

struct ServiceCabinBrackets: Shape {
    var arm: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let a = min(arm, min(rect.width, rect.height) / 3)
        path.addLines([
            CGPoint(x: rect.minX, y: rect.minY + a),
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.minX + a, y: rect.minY)
        ])
        path.move(to: CGPoint(x: rect.maxX - a, y: rect.minY))
        path.addLines([
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + a)
        ])
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - a))
        path.addLines([
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.maxX - a, y: rect.maxY)
        ])
        path.move(to: CGPoint(x: rect.minX + a, y: rect.maxY))
        path.addLines([
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - a)
        ])
        return path
    }
}

struct ServiceCabinWell<Content: View>: View {
    var powered: Bool
    var emphasis: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(powered ? 0.55 : 0.72))
                    Rectangle()
                        .fill(Color.white.opacity(powered ? 0.045 : 0.018))
                    LinearGradient(
                        colors: [
                            Color.black.opacity(powered ? 0.42 : 0.22),
                            Color.clear,
                            Color.white.opacity(powered ? 0.05 : 0.015)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    if powered {
                        ServiceCabinScanlines()
                            .opacity(0.22)
                            .blendMode(.normal)
                    }
                }
            }
            .overlay {
                ServiceCabinBrackets()
                    .stroke(
                        powered
                            ? LEDPhosphor.on.opacity(emphasis ? 0.82 : 0.48)
                            : Color.white.opacity(0.12),
                        lineWidth: 1.35
                    )
                    .padding(4)
            }
            .overlay {
                Rectangle()
                    .strokeBorder(
                        Color.white.opacity(powered ? 0.12 : 0.05),
                        lineWidth: 1.5
                    )
            }
            .shadow(
                color: powered ? LEDPhosphor.on.opacity(emphasis ? 0.28 : 0.12) : .clear,
                radius: powered ? 18 : 0
            )
            .opacity(powered ? 1 : 0.22)
            .animation(.easeInOut(duration: 0.52), value: powered)
            .animation(.easeInOut(duration: 0.52), value: emphasis)
    }
}

struct ServiceCabinLampBank: View {
    var lamp: ServiceCabinLamp

    private let cells: [(threshold: ServiceCabinLamp, label: String)] = [
        (.lamp, "運行"),
        (.occupancy, "占有"),
        (.phosphor, "案内"),
        (.boardReady, "発車"),
        (.circuits, "回路")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: FocusPanel.hairlineWidth)
                    }
                    lampCell(cell)
                }
            }
            GeometryReader { geo in
                let progress = CGFloat(lamp.rawValue) / CGFloat(ServiceCabinLamp.circuits.rawValue)
                Rectangle()
                    .fill(LEDPhosphor.on.opacity(lamp == .dark ? 0 : 0.9))
                    .frame(width: max(geo.size.width * progress, lamp == .dark ? 0 : 6), height: 2)
                    .shadow(color: LEDPhosphor.on.opacity(0.7), radius: 6)
            }
            .frame(height: 2)
        }
        .background(Color.white.opacity(0.03))
        .overlay {
            Rectangle()
                .strokeBorder(Color.white.opacity(0.16), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("表示灯")
    }

    private func lampCell(_ cell: (threshold: ServiceCabinLamp, label: String)) -> some View {
        let on = lamp >= cell.threshold
        return VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 16, height: 16)
                Circle()
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(on ? LEDPhosphor.on : Color.white.opacity(0.10))
                    .frame(width: 9, height: 9)
                    .shadow(color: on ? LEDPhosphor.on.opacity(1) : .clear, radius: on ? 10 : 0)
            }
            Text(cell.label)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(1.4)
                .foregroundStyle(on ? LEDPhosphor.on : FocusPanel.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(on ? 0.06 : 0.02),
                    Color.black.opacity(0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .accessibilityLabel(cell.label)
        .accessibilityValue(on ? "点灯" : "消灯")
    }
}

struct ServiceCabinKey: View {
    var title: String
    var kind: Kind = .stand
    var enabled: Bool = true
    var compact: Bool = false
    var action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    enum Kind {
        case stand
        case power
        case cancel
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .default))
                .tracking(kind == .power || kind == .stand ? (compact ? 3 : 5) : 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 12 : 18)
                .foregroundStyle(foreground)
                .background {
                    ZStack {
                        fill
                        LinearGradient(
                            colors: [
                                Color.white.opacity(enabled ? (isDark ? 0.14 : 0.35) : 0.04),
                                Color.clear,
                                Color.black.opacity(isDark ? 0.38 : 0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .overlay {
                    Rectangle()
                        .strokeBorder(stroke, lineWidth: 1.4)
                }
                .shadow(
                    color: keyGlow,
                    radius: enabled ? (isDark ? 10 : 0) : 0
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(title)
    }

    private var isDark: Bool { colorScheme == .dark }

    private var dimInk: Color {
        isDark ? FocusPanel.dim : Color.secondary
    }

    private var foreground: Color {
        switch kind {
        case .stand: enabled ? (isDark ? LEDPhosphor.on : TrainTheme.rail) : dimInk
        case .power: enabled ? TrainTheme.signalRed : dimInk
        case .cancel: isDark ? FocusPanel.muted : Color.secondary
        }
    }

    private var fill: Color {
        switch kind {
        case .stand: isDark ? Color.white.opacity(0.045) : TrainTheme.rail.opacity(0.10)
        case .power: TrainTheme.signalRed.opacity(enabled ? (isDark ? 0.16 : 0.12) : 0.05)
        case .cancel: Color.primary.opacity(isDark ? 0.03 : 0.04)
        }
    }

    private var stroke: Color {
        switch kind {
        case .stand:
            isDark
                ? LEDPhosphor.on.opacity(enabled ? 0.55 : 0.12)
                : TrainTheme.rail.opacity(enabled ? 0.55 : 0.18)
        case .power: TrainTheme.signalRed.opacity(enabled ? 0.7 : 0.14)
        case .cancel: Color.primary.opacity(isDark ? 0.16 : 0.18)
        }
    }

    private var keyGlow: Color {
        switch kind {
        case .stand: isDark ? LEDPhosphor.on.opacity(enabled ? 0.22 : 0) : .clear
        case .power: TrainTheme.signalRed.opacity(enabled && isDark ? 0.28 : 0)
        case .cancel: .clear
        }
    }
}
