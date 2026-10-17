//
//  FocusUndoBanner.swift
//  Todo train
//

import SwiftUI

struct FocusUndoBanner: View {
    let offer: SessionManager.FocusUndoOffer
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(offer.message)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Button("取り消し", action: onUndo)
                .font(.subheadline.weight(.bold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(FocusPanel.fillRaised.opacity(0.96))
        .padding(.horizontal, 8)
        .padding(.top, 6)
    }
}
