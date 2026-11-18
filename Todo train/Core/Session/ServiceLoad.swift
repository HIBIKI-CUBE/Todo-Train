//
//  ServiceLoad.swift
//  Todo train
//
//  LOAD: 範囲終端までの空きと、TODAY 区切りより上の切符の所要合計。
//

import Foundation

nonisolated struct ServiceLoadTicket: Equatable, Sendable {
  /// 予測の中央値（分）。
  var durationMinutes: Int
}

nonisolated struct ServiceLoadSnapshot: Equatable, Sendable {
  var freeMinutes: Int
  var ticketMinutes: Int
  var overflowMinutes: Int
  var fitsWithinFree: Bool
}

nonisolated enum ServiceLoadLogic {
  static func compute(
    now: Date,
    range: TimetableRange,
    adoptedBlocks: [TimetableOpeningInterval],
    ticketsAboveCutoff: [ServiceLoadTicket]
  ) -> ServiceLoadSnapshot {
    let freeMinutes = freeCapacity(
      now: now,
      rangeEnd: range.endsAt,
      adoptedBlocks: adoptedBlocks
    )
    let ticketMinutes = ticketsAboveCutoff.reduce(0) { $0 + max(0, $1.durationMinutes) }
    let overflow = max(0, ticketMinutes - freeMinutes)
    return ServiceLoadSnapshot(
      freeMinutes: freeMinutes,
      ticketMinutes: ticketMinutes,
      overflowMinutes: overflow,
      fitsWithinFree: ticketMinutes <= freeMinutes
    )
  }

  private static func freeCapacity(
    now: Date,
    rangeEnd: Date,
    adoptedBlocks: [TimetableOpeningInterval]
  ) -> Int {
    guard now < rangeEnd else { return 0 }

    var free = rangeEnd.timeIntervalSince(now)
    for block in adoptedBlocks where block.endsAt > block.startsAt {
      let overlapStart = max(now, block.startsAt)
      let overlapEnd = min(rangeEnd, block.endsAt)
      if overlapEnd > overlapStart {
        free -= overlapEnd.timeIntervalSince(overlapStart)
      }
    }
    return max(0, Int(free / 60))
  }
}