//
//  SafetyLockOverrideControl.swift
//  Todo train
//

import SwiftUI

/// Cover unlock + slide-to-confirm for temporary pause override.
struct SafetyLockOverrideControl: View {
    let todayCount: Int
    let onConfirm: () -> Void

    @State private var coverLifted = false
    @State private var dragOffset: CGFloat = 0

    private let trackWidth: CGFloat = 260
    private let thumbSize: CGFloat = 44
    private var maxDrag: CGFloat { trackWidth - thumbSize - 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !coverLifted {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        coverLifted = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "lock.fill")
                        Text("安全カバーを開ける")
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(TrainTheme.signalAmber.opacity(0.15))
                            .frame(width: trackWidth, height: thumbSize + 8)

                        Text("スライドして臨時停車")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)

                        Circle()
                            .fill(TrainTheme.signalAmber)
                            .frame(width: thumbSize, height: thumbSize)
                            .overlay {
                                Image(systemName: "chevron.right.2")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                            .offset(x: 4 + dragOffset)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        dragOffset = min(max(0, value.translation.width), maxDrag)
                                    }
                                    .onEnded { _ in
                                        if dragOffset >= maxDrag * 0.92 {
                                            dragOffset = maxDrag
                                            onConfirm()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                dragOffset = 0
                                                coverLifted = false
                                            }
                                        } else {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                dragOffset = 0
                                            }
                                        }
                                    }
                            )
                            .accessibilityHidden(true)
                    }
                    .frame(width: trackWidth)
                    .accessibilityHidden(true)

                    Button("臨時停車する", role: .destructive) {
                        onConfirm()
                        coverLifted = false
                        dragOffset = 0
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrainTheme.signalAmber)
                    .accessibilityHint("停車上限を超えて今の切符を停車します")
                }
            }
        }
    }

    private var caption: String {
        if todayCount == 0 {
            return "枠を増やさず、今の切符だけ臨時に停車します"
        }
        return "今日 \(todayCount) 回目の臨時停車（制限なし）"
    }
}
