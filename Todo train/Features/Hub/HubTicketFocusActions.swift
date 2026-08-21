//
//  HubTicketFocusActions.swift
//  Todo train
//
//  Bottom cabin console under a focused Hub ticket — Focus panel language,
//  not a Mars stub and not a floating HIG card.
//

import SwiftUI

struct HubTicketFocusActions: View {
    let canBoard: Bool
    let disabledReason: String?
    var revealed: Bool = true
    let onBoard: () -> Void
    let onOpenDetail: () -> Void

    private let rowHeight = MarsTicketSpec.HubStack.focusConsoleRowHeight

    var body: some View {
        VStack(spacing: 0) {
            FocusControlDivider()

            HStack(spacing: 0) {
                Button(action: onOpenDetail) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text")
                            .font(.body.weight(.semibold))
                        Text("詳細")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    FocusControlCellStyle(
                        fill: FocusPanel.fillRaised,
                        foreground: FocusPanel.ink
                    )
                )
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.38 }
                .accessibilityLabel("詳細")
                .accessibilityHint("切符の詳細を開く")

                FocusControlVerticalDivider()

                Button(action: onBoard) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(canBoard ? Color.black.opacity(0.35) : FocusPanel.dim)
                            .frame(width: 8, height: 8)
                        Text("発車")
                            .font(.title3.weight(.bold))
                            .tracking(4)
                        Image(systemName: "tram.fill")
                            .font(.body.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(
                    FocusControlCellStyle(
                        fill: canBoard ? TrainTheme.signalGreen : FocusPanel.fillRaised,
                        foreground: canBoard ? .black : FocusPanel.dim
                    )
                )
                .frame(maxWidth: .infinity)
                .disabled(!canBoard)
                .accessibilityLabel("発車")
                .accessibilityHint(canBoard ? "運転台へ乗務" : (disabledReason ?? "発車できません"))
            }
            .frame(height: rowHeight)

            if !canBoard, let disabledReason, !disabledReason.isEmpty {
                FocusControlDivider()
                Text(disabledReason)
                    .font(.caption2)
                    .foregroundStyle(FocusPanel.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
        }
        .background {
            Color.black.ignoresSafeArea(edges: .bottom)
        }
        .opacity(revealed ? 1 : 0)
        .allowsHitTesting(revealed)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        Color.black.opacity(0.45).ignoresSafeArea()
        VStack {
            MarsTicketView(
                content: MarsTicketContent(title: "週次レビュー", minutes: 25),
                density: .hub
            )
            .padding(.horizontal, 24)
            Spacer()
        }
        HubTicketFocusActions(
            canBoard: true,
            disabledReason: nil,
            onBoard: {},
            onOpenDetail: {}
        )
    }
}
