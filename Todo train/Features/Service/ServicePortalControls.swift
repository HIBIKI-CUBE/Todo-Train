//
//  ServicePortalControls.swift
//  Todo train
//
//  起動は地平の生きもの。発車用意は棚の縁。押し続けで部屋が締まる。
//

import SwiftUI

struct PortalIgnitionBar: View {
    var title: String
    var skipAfter: TimeInterval
    var breath: Double
    var handoff: Double
    var reduceMotion: Bool
    var onTap: () -> Void
    var onSkip: () -> Void

    @State private var pressStarted: Date?
    @State private var pressed = false

    var body: some View {
        let glow = pressed ? 1.0 : 0.52 + 0.48 * breath
        ZStack {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.10 + 0.16 * glow))
                .blur(radius: reduceMotion ? 0 : 18)
                .scaleEffect(x: 1.08, y: 2.4)
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.14 + 0.22 * glow))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55 + 0.40 * glow), lineWidth: 1.4)
                }
                .shadow(color: Color.white.opacity(0.28 + 0.50 * glow), radius: 22 * glow)
            Text(title)
                .font(.system(size: 28, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .shadow(color: Color.white.opacity(0.7), radius: 10)
        }
        .frame(height: 64)
        .scaleEffect(pressed ? 0.985 : 0.97 + 0.03 * breath)
        .opacity(max(0, 1 - handoff))
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint("今日の運行の内側を起こす。長押しで揃えを短くする")
        .accessibilityAction {
            onTap()
        }
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if pressStarted == nil {
                    pressStarted = .now
                    pressed = true
                }
            }
            .onEnded { _ in
                let duration = Date.now.timeIntervalSince(pressStarted ?? .now)
                pressStarted = nil
                pressed = false
                if duration >= skipAfter {
                    onSkip()
                } else {
                    onTap()
                }
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
        GeometryReader { geo in
            let spread = max(12, geo.size.width * current)
            ZStack {
                Rectangle()
                    .fill(Color.white.opacity(0.06 + 0.10 * current))
                Rectangle()
                    .fill(Color.white.opacity(0.16 + 0.52 * current))
                    .frame(width: spread)
                    .shadow(color: Color.white.opacity(0.55 * current), radius: 18 * current)
                if !reduceMotion, current > 0.04 {
                    Rectangle()
                        .fill(Color.white.opacity(0.16 * current))
                        .blur(radius: 14)
                        .frame(width: spread * 1.15, height: geo.size.height * 1.8)
                }
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.white.opacity(0.35 + 0.45 * current), radius: 8)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.35 + 0.50 * current))
                    .frame(height: 2)
                    .shadow(color: Color.white.opacity(0.6 * current), radius: 8)
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
