//
//  HubStationChevronSign.swift
//  Todo train
//
//  Station LED board: ">>> 発車 >>>" in chunky dots.
//  Hub present overlay only (not a sibling in the deck ForEach).
//

import SwiftUI

struct HubDepartLEDSign: View {
    var canBoard: Bool
    var ticketWidth: CGFloat
    var ticketHeight: CGFloat

    private var signHeight: CGFloat {
        ticketHeight * MarsTicketSpec.HubStack.departSignHeightRatio
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !canBoard)) { timeline in
            let phase = chasePhase(at: timeline.date)
            let chevronH = signHeight * 0.46
            let chevronW = chevronH * 0.7
            HStack(spacing: signHeight * 0.06) {
                LEDChevronRun(
                    count: 3,
                    phase: phase,
                    lit: canBoard,
                    reverse: false,
                    chevronSize: CGSize(width: chevronW, height: chevronH)
                )
                LEDDepartWord(lit: canBoard, height: signHeight * 0.38)
                LEDChevronRun(
                    count: 3,
                    phase: phase,
                    lit: canBoard,
                    reverse: false,
                    chevronSize: CGSize(width: chevronW, height: chevronH)
                )
            }
            .padding(.horizontal, signHeight * 0.1)
            .frame(width: ticketWidth, height: signHeight)
            .clipped()
            .background { housing }
        }
        .frame(width: ticketWidth, height: signHeight)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .drawingGroup()
    }

    private var housing: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.black.opacity(0.9))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(TrainTheme.signalGreen.opacity(canBoard ? 0.5 : 0.18), lineWidth: 1.2)
            }
            .shadow(color: TrainTheme.signalGreen.opacity(canBoard ? 0.4 : 0), radius: 12, y: 2)
    }

    private func chasePhase(at date: Date) -> Double {
        date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
    }
}

private struct LEDChevronRun: View {
    var count: Int
    var phase: Double
    var lit: Bool
    var reverse: Bool
    var chevronSize: CGSize

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                LEDChevronDots()
                    .fill(fill(index: index))
                    .frame(width: chevronSize.width, height: chevronSize.height)
            }
        }
    }

    private func fill(index: Int) -> Color {
        guard lit else { return TrainTheme.signalGreen.opacity(0.16) }
        let slot = Double(index) / Double(max(count, 1))
        var delta = reverse ? (slot - phase) : (phase - slot)
        if delta < 0 { delta += 1 }
        let head = max(0, 1 - delta * 2.1)
        return TrainTheme.signalGreen.opacity(0.3 + head * 0.7)
    }
}

private struct LEDChevronDots: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cols = 4
        let rows = 7
        let dot = min(rect.width / 4.6, rect.height / 7.6)
        let xStep = (rect.width - dot) / CGFloat(cols - 1)
        let yStep = (rect.height - dot) / CGFloat(rows - 1)
        for col in 0..<cols {
            let litRows: [Int]
            switch col {
            case 0: litRows = [0, 6]
            case 1: litRows = [1, 5]
            case 2: litRows = [2, 4]
            default: litRows = [3]
            }
            for row in litRows {
                path.addEllipse(
                    in: CGRect(
                        x: CGFloat(col) * xStep,
                        y: CGFloat(row) * yStep,
                        width: dot,
                        height: dot
                    )
                )
            }
        }
        return path
    }
}

private struct LEDDepartWord: View {
    var lit: Bool
    var height: CGFloat

    var body: some View {
        Text("発車")
            .font(.system(size: height, weight: .heavy, design: .rounded))
            .foregroundStyle(.clear)
            .overlay {
                LEDDotField(lit: lit)
                    .mask(
                        Text("発車")
                            .font(.system(size: height, weight: .heavy, design: .rounded))
                    )
            }
            .fixedSize()
            .shadow(color: TrainTheme.signalGreen.opacity(lit ? 0.55 : 0), radius: 6)
    }
}

private struct LEDDotField: View {
    var lit: Bool

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 6.5
            let dot: CGFloat = 4.2
            let cols = Int(size.width / pitch) + 2
            let rows = Int(size.height / pitch) + 2
            let color = TrainTheme.signalGreen.opacity(lit ? 1 : 0.2)
            for row in 0..<rows {
                for col in 0..<cols {
                    let rect = CGRect(
                        x: CGFloat(col) * pitch,
                        y: CGFloat(row) * pitch,
                        width: dot,
                        height: dot
                    )
                    context.fill(Path(ellipseIn: rect), with: .color(color))
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
        VStack(spacing: 12) {
            HubDepartLEDSign(canBoard: true, ticketWidth: 320, ticketHeight: 210)
            RoundedRectangle(cornerRadius: 2.5)
                .fill(MarsTicketSpec.paper)
                .frame(width: 320, height: 210)
        }
    }
}
