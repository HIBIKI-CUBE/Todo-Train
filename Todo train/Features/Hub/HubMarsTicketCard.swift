//
//  HubMarsTicketCard.swift
//  Todo train
//
//  Full Mars face in the Hub deck (covering creates peeks; focus overlay owns CTAs).
//  Keep this view flat — tilt is applied outside matchedGeometry so focus morph stays continuous.
//

import SwiftUI

struct HubMarsTicketCard: View {
    let ticket: Ticket
    let onSelect: () -> Void

    private var content: MarsTicketContent {
        MarsTicketContent(ticket: ticket)
    }

    var body: some View {
        MarsTicketView(content: content, density: .hub)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("選択して発車または詳細")
    }
}

#Preview {
    let ticket = Ticket(title: "週次レビュー", estimatedSeconds: 1_500, sortOrder: 0)
    return HubMarsTicketCard(ticket: ticket, onSelect: {})
        .padding()
        .background(Color(uiColor: .systemGroupedBackground))
}
