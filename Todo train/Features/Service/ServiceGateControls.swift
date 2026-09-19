//
//  ServiceGateControls.swift
//  Todo train
//
//  起動と発車用意。押す前の予兆と、ホールド中の画面側の緊張。
//

import SwiftUI

struct IgnitionPressControl: View {
    var title: String
    var skipAfter: TimeInterval
    @Binding var pressed: Bool
    var reduceMotion: Bool
    var onTap: () -> Void
    var onSkip: () -> Void

    @State private var pressStarted: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 1 : 0.04)) { context in
            ignitionFace(at: context.date)
        }
        .contentShape(Rectangle())
        .gesture(pressGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityAction {
            onTap()
        }
    }

    private func ignitionFace(at date: Date) -> some View {
        let breath = reduceMotion ? 0.55 : (sin(date.timeIntervalSinceReferenceDate * 1.7) + 1) / 2
        let glow = pressed ? 1.0 : 0.55 + 0.45 * breath
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.22 + 0.20 * glow))
                .blur(radius: reduceMotion ? 0 : 16)
                .scaleEffect(x: 1.12, y: 1.55)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.16 + 0.14 * glow))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55 + 0.35 * glow), lineWidth: 1.2)
                }
                .shadow(color: Color.white.opacity(0.35 + 0.40 * glow), radius: 18 * glow)
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundStyle(Color.white)
                .shadow(color: Color.white.opacity(0.6), radius: 8)
        }
        .scaleEffect(pressed ? 0.97 : 0.98 + 0.02 * breath)
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

struct PrimeHoldControl: View {
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
            holdFace(progress: current)
        }
        .contentShape(Rectangle())
        .gesture(holdGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(title)
        .accessibilityHint("押し続ける")
        .accessibilityAction {
            onBegan()
            onCompleted()
        }
    }

    private func holdFace(progress current: Double) -> some View {
        GeometryReader { geo in
            let fillHeight = max(8, geo.size.height * current)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.10 + 0.10 * current))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.22 + 0.55 * current))
                    .frame(height: fillHeight)
                    .shadow(color: Color.white.opacity(0.45 * current), radius: 16 * current)
                if !reduceMotion, current > 0.04 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.18 * current))
                        .blur(radius: 12)
                        .frame(height: fillHeight)
                }
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .default))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.white.opacity(0.4 + 0.4 * current), radius: 8)
            }
        }
        .padding(.horizontal, 18)
        .opacity(enabled ? 1 : 0.45)
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
