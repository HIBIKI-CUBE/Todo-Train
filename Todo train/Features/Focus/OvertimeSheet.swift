//
//  OvertimeSheet.swift
//  Todo train
//

import AudioToolbox
import SwiftUI

struct OvertimeOverlay: View {
    let onAlreadyDone: () -> Void
    let onJustFinished: () -> Void
    let onExtend: (TimeInterval) -> Void

    @State private var showExtendChips = false

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
                        onExtend(TimeInterval(minutes * 60))
                        showExtendChips = false
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

                        Button("ちょうど終わった") { onJustFinished() }
                            .buttonStyle(FocusPrimaryButtonStyle())

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
