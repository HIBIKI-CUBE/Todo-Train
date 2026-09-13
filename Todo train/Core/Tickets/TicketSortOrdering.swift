//
//  TicketSortOrdering.swift
//  Todo train
//
//  Pure helpers for Hub / Quick Add / 乗り継ぎ insertion positions.
//

import Foundation

enum TicketInsertionPosition: Equatable, Hashable, Sendable {
    case start
    case end
    case after(UUID)
}

enum TicketSortOrdering {
    /// Index into the current open-ticket order where a new ticket should be inserted.
    static func insertionIndex(
        openIDsOrdered: [UUID],
        position: TicketInsertionPosition
    ) -> Int {
        switch position {
        case .start:
            return 0
        case .end:
            return openIDsOrdered.count
        case .after(let id):
            if let index = openIDsOrdered.firstIndex(of: id) {
                return index + 1
            }
            return openIDsOrdered.count
        }
    }

    /// Returns contiguous sortOrder values (0..<n) for the given order.
    static func normalizedOrders(forOrderedIDs ids: [UUID]) -> [UUID: Int] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
    }
}
