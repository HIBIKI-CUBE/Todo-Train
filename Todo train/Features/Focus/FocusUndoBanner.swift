//
//  FocusUndoBanner.swift
//  Todo train
//

import SwiftUI

struct FocusUndoBanner: View {
    let offer: SessionManager.FocusUndoOffer
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(offer.recordedStatusLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FocusPanel.ink)
            Spacer(minLength: 8)
            Button("取り消す", action: onUndo)
                .font(.subheadline.weight(.bold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .padding(.horizontal, TrainTheme.Space.lg)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(FocusPanel.fillRaised)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(offer.recordedStatusLine)、取り消す")
    }
}

extension SessionManager.FocusUndoOffer {
    var recordedStatusLine: String {
        switch kind {
        case .pause:
            return "停車を記録しました"
        case .reestimate:
            return "見積もり直しを記録しました"
        }
    }
}
