//
//  ServicePortalControls.swift
//  Todo train
//
//  起動は触れた拍で部屋を起こす。発車用意は押し始めから部屋が主。
//

import SwiftUI

struct PortalIgnitionBar: View {
    var title: String
    var skipAfter: TimeInterval
    var breath: Double
    var handoff: Double
    var reduceMotion: Bool
    var onIgnite: () -> Void
    var onHoldSkip: () -> Void

    @State private var pressStarted: Date?
    @State private var pressed = false
    @State private var didSkip = false

    var body: some View {
        let glow = pressed ? 1.0 : 0.52 + 0.48 * breath
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12 + 0.22 * glow))
                .blur(radius: reduceMotion ? 0 : 22)
                .scaleEffect(x: 1.16, y: 2.8)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16 + 0.28 * glow))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55 + 0.40 * glow), lineWidth: 1.4)
                }
                .shadow(color: Color.white.opacity(0.32 + 0.55 * glow), radius: 26 * glow)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .shadow(color: Color.white.opacity(0.7), radius: 10)
        }
        .frame(height: 64)
        .scaleEffect(pressed ? 0.97 : 0.97 + 0.03 * breath)
        .opacity(max(0, 1 - handoff))
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint("今日の運行の内側を起こす。長押しで揃えを短くする")
        .accessibilityAction {
            onIgnite()
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressStarted == nil {
                    pressStarted = .now
                    pressed = true
                    onIgnite()
                } else if !didSkip, let pressStarted,
                          Date.now.timeIntervalSince(pressStarted) >= skipAfter {
                    didSkip = true
                    onHoldSkip()
                }
            }
            .onEnded { _ in
                pressStarted = nil
                pressed = false
                didSkip = false
            }
    }
}

struct PortalPrimeLip: View {
    var title: String
    var holdSeconds: TimeInterval
    @Binding var progress: Double
    var enabled: Bool
    var reduceMotion: Bool
    var onBegan: () -> Void
    var onCancelled: () -> Void
    var onCompleted: () -> Void

    @State private var pressStarted: Date?
    @State private var holding = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: holding ? 0.03 : 1)) { context in
            let current = currentProgress(at: context.date)
            lipFace(progress: current)
        }
        .frame(height: 72)
        .contentShape(Rectangle())
        .gesture(holdGesture)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint("押し続けてホームへ出る")
        .accessibilityAction {
            onBegan()
            onCompleted()
        }
    }

    private func lipFace(progress current: Double) -> some View {
        let charge = ServicePortalSequence.primeRoomCharge(progress: current)
        return GeometryReader { geo in
            let spread = max(12, geo.size.width * current)
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.06 + 0.14 * charge))
                Rectangle()
                    .fill(Color.white.opacity(0.18 + 0.50 * current))
                    .frame(width: spread)
                    .shadow(color: Color.white.opacity(0.55 * current), radius: 18 * current)
                if !reduceMotion, charge > 0.04 {
                    Rectangle()
                        .fill(Color.white.opacity(0.22 * charge))
                        .blur(radius: 16)
                        .frame(width: max(spread * 1.2, geo.size.width * 0.4 * charge), height: geo.size.height * 2.4)
                }
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.white.opacity(0.35 + 0.50 * charge), radius: 8)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.40 + 0.55 * charge))
                    .frame(height: 2)
                    .shadow(color: Color.white.opacity(0.7 * charge), radius: 10)
            }
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard enabled else { return }
                if pressStarted == nil {
                    pressStarted = .now
                    holding = true
                    onBegan()
                }
                if let pressStarted {
                    let value = min(1, Date.now.timeIntervalSince(pressStarted) / holdSeconds)
                    progress = value
                    if value >= 1 {
                        finish()
                    }
                }
            }
            .onEnded { _ in
                guard holding else { return }
                if progress >= 1 {
                    finish()
                } else {
                    holding = false
                    pressStarted = nil
                    progress = 0
                    onCancelled()
                }
            }
    }

    private func currentProgress(at date: Date) -> Double {
        guard let pressStarted, holding else { return progress }
        return min(1, date.timeIntervalSince(pressStarted) / holdSeconds)
    }

    private func finish() {
        guard holding else { return }
        holding = false
        pressStarted = nil
        progress = 1
        onCompleted()
    }
}
