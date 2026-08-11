//
//  InsertPositionPicker.swift
//  Todo train
//

import SwiftUI

struct InsertPositionPicker: View {
    let openTickets: [Ticket]
    @Binding var position: TicketInsertionPosition

    var body: some View {
        Picker("挿入位置", selection: $position) {
            Text("末尾（デフォルト）").tag(TicketInsertionPosition.end)
            Text("先頭").tag(TicketInsertionPosition.start)
            ForEach(openTickets, id: \.id) { ticket in
                Text("「\(ticket.title)」の直後")
                    .tag(TicketInsertionPosition.after(ticket.id))
                    .lineLimit(1)
            }
        }
    }
}
