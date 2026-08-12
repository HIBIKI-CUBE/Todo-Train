//
//  OvertimeSheet.swift
//  Todo train
//

import AudioToolbox
import SwiftUI

struct OvertimeOverlay: View {
    let onAlreadyDone: () -> Void
    let onJustFinished: () -> Void
    let onExtend: (TimeInterval, String?) -> Void

    @State private var showExtendChips = false
    @State private var selectedReason: String?

    private let reasonPresets = ["見積もりが甘かった", "割り込みが入った", "もう少しで終わる", "その他"]

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: TrainTheme.Space.lg) {
                VStack(spacing: TrainTheme.Space.sm) {
                    SignalBadge(kind: .overtime)
                    Text("見積もりを過ぎました")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                }

                if showExtendChips {
                    Text("どのくらい伸ばしますか？")
                        .foregroundStyle(.white.opacity(0.85))
                    EstimateChips { minutes in
                        onExtend(TimeInterval(minutes * 60), selectedReason)
                        showExtendChips = false
                        selectedReason = nil
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("なぜ？（任意）")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                        FlowReasonChips(reasons: reasonPresets, selected: $selectedReason)
                    }

                    Button("戻る") {
                        withAnimation(TrainTheme.Motion.soft) {
                            showExtendChips = false
                        }
                    }
                    .foregroundStyle(.white.opacity(0.75))
                } else {
                    VStack(spacing: TrainTheme.Space.sm) {
                        Button("もう終わってた") { onAlreadyDone() }
                            .buttonStyle(FocusPrimaryButtonStyle())
                            .accessibilityHint("すでに完了していたとして到着します")

                        Button("ちょうど終わった") { onJustFinished() }
                            .buttonStyle(FocusPrimaryButtonStyle())
                            .accessibilityHint("いま到着として記録します")

                        Button("延長する") {
                            withAnimation(TrainTheme.Motion.soft) {
                                showExtendChips = true
                            }
                        }
                        .buttonStyle(FocusSecondaryButtonStyle())
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(TrainTheme.cabinLift)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(TrainTheme.signalRed.opacity(0.35), lineWidth: 1)
                    }
            )
        }
    }

    static func playAlertSound() {
        AudioServicesPlaySystemSound(1005)
    }
}

private struct FlowReasonChips: View {
    let reasons: [String]
    @Binding var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(reasons, id: \.self) { reason in
                Button {
                    selected = selected == reason ? nil : reason
                } label: {
                    Text(reason)
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected == reason ? TrainTheme.rail.opacity(0.35) : TrainTheme.cabin.opacity(0.55))
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .accessibilityAddTraits(selected == reason ? .isSelected : [])
            }
        }
    }
}
