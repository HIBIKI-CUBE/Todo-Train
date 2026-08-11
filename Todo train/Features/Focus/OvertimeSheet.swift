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
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("見積もりを過ぎました")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                if showExtendChips {
                    Text("どのくらい伸ばしますか？")
                        .foregroundStyle(.white.opacity(0.9))
                    EstimateChips { minutes in
                        onExtend(TimeInterval(minutes * 60))
                        showExtendChips = false
                    }
                    Button("戻る") {
                        showExtendChips = false
                    }
                    .foregroundStyle(.white.opacity(0.8))
                } else {
                    VStack(spacing: 12) {
                        Button("もう終わってた") { onAlreadyDone() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                        Button("ちょうど終わった") { onJustFinished() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                        Button("延長する") {
                            showExtendChips = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.white)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 340)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    static func playAlertSound() {
        AudioServicesPlaySystemSound(1005)
    }
}
