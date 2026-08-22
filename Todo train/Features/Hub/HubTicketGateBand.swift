//
//  HubTicketGateBand.swift
//  Todo train
//
//  Magnetic / 改札 band printed on the Mars face. Holding the ticket, this is 発車.
//  Not a HIG pill and not Focus's cabin grid.
//

import SwiftUI

struct HubTicketGateBand: View {
    let canBoard: Bool
    let disabledReason: String?
    /// Only the held ticket's band is live; stacked peeks pass taps through to select.
    var armed: Bool = false
    let onBoard: () -> Void

    var body: some View {
        Button(action: onBoard) {
            HStack(spacing: 10) {
                Circle()
                    .fill(MarsTicketSpec.paper.opacity(canBoard ? 0.95 : 0.35))
                    .frame(width: 7, height: 7)
                Text("発車")
                    .font(.headline.weight(.bold))
                    .tracking(6)
                Image(systemName: "tram.fill")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(MarsTicketSpec.paper)
            .frame(maxWidth: .infinity)
            .frame(height: MarsTicketSpec.HubStack.gateBandHeight)
            .background(stripe)
        }
        .buttonStyle(HubGatePressStyle())
        .disabled(!armed || !canBoard)
        .allowsHitTesting(armed)
        .accessibilityLabel("発車")
        .accessibilityHint(
            canBoard
                ? "改札に通して運転台へ"
                : (disabledReason ?? "発車できません")
        )
    }

    private var stripe: some View {
        Rectangle()
            .fill(MarsTicketSpec.printInk.opacity(canBoard ? 1 : 0.28))
    }
}

private struct HubGatePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1, anchor: .bottom)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
