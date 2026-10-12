//
//  ArrivalGapBanner.swift
//  Todo train
//
//  Hub only. Focus does not preview the next ticket from this blank.
//

import SwiftUI
import TodoTrainSync

struct ArrivalGapBanner: View {
    var state: ArrivalGapBannerState
    var onBoard: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.sm) {
            HStack(spacing: 8) {
                Circle()
                    .fill(state.holdLamp ? TrainTheme.rail : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(state.prompt)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(CabinCopy.gapPromptHint)

            HStack(spacing: TrainTheme.Space.sm) {
                if state.ticketID != nil {
                    Button(CabinCopy.board, action: onBoard)
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint(CabinCopy.boardHint)
                }
                Button(CabinCopy.close, action: onClose)
                    .buttonStyle(.bordered)
                    .accessibilityHint(CabinCopy.closeGapHint)
            }
        }
        .padding(TrainTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
