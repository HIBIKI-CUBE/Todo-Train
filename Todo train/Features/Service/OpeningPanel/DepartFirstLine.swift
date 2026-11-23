//
//  DepartFirstLine.swift
//  Todo train
//
//  DEPART 横の先発の行。TICKETS の先頭を 10pt の一行に出す。
//

import SwiftUI

struct DepartFirstLine: View {
    var row: OpeningPanelTicketRow?
    var isLit: Bool
    var growthStep: Int

    var body: some View {
        Group {
            if isLit, let row {
                let presentation = OpeningPanelTickets.durationPresentation(
                    arrival: row.arrival,
                    estimate: row.estimateMinutes,
                    growthStep: growthStep
                )
                HStack(spacing: 6) {
                    Text("先発")
                        .opacity(0.75)
                    Text(row.title)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(presentation.text)
                        .monospacedDigit()
                        .opacity(presentation.faint ? OpeningPanelTicketMetrics.staleDurationOpacity : 1)
                }
                .font(.system(size: OpeningPanelTokens.TypeSize.departLine))
                .foregroundStyle(OpeningPanelTokens.Palette.amber)
                .lineLimit(1)
                .padding(.horizontal, 5)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("先発 \(row.title)")
                .accessibilityValue(presentation.text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
