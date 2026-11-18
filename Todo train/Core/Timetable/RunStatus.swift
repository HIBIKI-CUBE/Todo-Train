//
//  RunStatus.swift
//  Todo train
//
//  運転状況・ただいま板・NEXT。着発した予定だけを数える。
//

import Foundation

nonisolated enum RunStatusKind: Equatable, Sendable {
    case normal
    case dense
    case hold
}

nonisolated struct RunStatusBand: Equatable, Sendable, Identifiable {
    var startsAt: Date
    var endsAt: Date
    var kind: RunStatusKind

    var id: Date { startsAt }
}

nonisolated enum RunStatusNowCase: Equatable, Sendable {
  case beforeStart(minutesUntilNextNormal: Int, nextNormalDurationMinutes: Int)
  case ridingNormal(remainingMinutes: Int, endsAt: Date)
  case waitingForNormal(
    status: RunStatusKind,
    minutesUntilNextNormal: Int,
    nextNormalDurationMinutes: Int
  )
  case afterLastNormal(status: RunStatusKind)
  case afterRangeEnd
}

nonisolated struct RunStatusNow: Equatable, Sendable {
  var caseKind: RunStatusNowCase
  var referencedNormalBand: RunStatusBand?
}

nonisolated struct RunStatusNext: Equatable, Sendable {
  /// いまの帯の終わり（着発した予定の中にいるとき、重なりをつないだ終端）。
  var currentBandEndsAt: Date?
  /// 予定の外にいるとき、次の着発の始まり。
  var nextStopInTarget: Date?
  /// 予定の中にいるとき、その占有の終わり。
  var nextRideInTarget: Date?
}

nonisolated enum RunStatusLogic {
  static let defaultNormalGapMinutes = 60
  static let defaultHoldThresholdMinutes = 30

  static func bands(
    range: TimetableRange,
    adoptedBlocks: [TimetableOpeningInterval],
    normalGapMinutes: Int = defaultNormalGapMinutes,
    holdThresholdMinutes: Int = defaultHoldThresholdMinutes
  ) -> [RunStatusBand] {
    let lo = range.startsAt
    let hi = range.endsAt
    guard hi > lo else { return [] }

    let merged = mergeAdopted(adoptedBlocks, lowerBound: lo, upperBound: hi)
    guard !merged.isEmpty else {
      return [RunStatusBand(startsAt: lo, endsAt: hi, kind: .normal)]
    }

    struct Piece {
      var startsAt: Date
      var endsAt: Date
      var isGap: Bool
      var kind: RunStatusKind?
    }

    var pieces: [Piece] = []
    var cursor = lo
    for block in merged {
      if block.startsAt > cursor {
        pieces.append(Piece(startsAt: cursor, endsAt: block.startsAt, isGap: true, kind: nil))
      }
      pieces.append(Piece(startsAt: block.startsAt, endsAt: block.endsAt, isGap: false, kind: nil))
      cursor = block.endsAt
    }
    if cursor < hi {
      pieces.append(Piece(startsAt: cursor, endsAt: hi, isGap: true, kind: nil))
    }

    let normalGap = TimeInterval(normalGapMinutes * 60)
    let holdThreshold = TimeInterval(holdThresholdMinutes * 60)

    for index in pieces.indices {
      let duration = pieces[index].endsAt.timeIntervalSince(pieces[index].startsAt)
      if pieces[index].isGap {
        pieces[index].kind = duration >= normalGap ? .normal : .dense
      } else if duration > holdThreshold {
        pieces[index].kind = .hold
      }
    }

    for index in pieces.indices where !pieces[index].isGap && pieces[index].kind == nil {
      let neighbors = [pieces[safe: index - 1], pieces[safe: index + 1]]
      let borderedByDense = neighbors.contains { neighbor in
        guard let neighbor, neighbor.isGap else { return false }
        return neighbor.kind == .dense
      }
      pieces[index].kind = borderedByDense ? .dense : .hold
    }

    var bands: [RunStatusBand] = []
    for piece in pieces {
      guard let kind = piece.kind else { continue }
      if let last = bands.last, last.kind == kind, last.endsAt == piece.startsAt {
        bands[bands.count - 1].endsAt = piece.endsAt
      } else {
        bands.append(RunStatusBand(startsAt: piece.startsAt, endsAt: piece.endsAt, kind: kind))
      }
    }
    return bands
  }

  static func nowReading(
    now: Date,
    range: TimetableRange,
    bands: [RunStatusBand]
  ) -> RunStatusNow {
    guard !bands.isEmpty else {
      return RunStatusNow(caseKind: .afterRangeEnd, referencedNormalBand: nil)
    }

    if now >= range.endsAt {
      return RunStatusNow(caseKind: .afterRangeEnd, referencedNormalBand: nil)
    }

    if now < range.startsAt {
      guard let nextNormal = bands.first(where: { $0.kind == .normal && $0.endsAt > now }) else {
        let status = bands.first?.kind ?? .dense
        return RunStatusNow(caseKind: .afterLastNormal(status: status), referencedNormalBand: nil)
      }
      let until = minutesBetween(from: now, to: nextNormal.startsAt)
      let length = minutesBetween(from: nextNormal.startsAt, to: nextNormal.endsAt)
      return RunStatusNow(
        caseKind: .beforeStart(minutesUntilNextNormal: until, nextNormalDurationMinutes: length),
        referencedNormalBand: nextNormal
      )
    }

    if let index = bands.firstIndex(where: { $0.startsAt <= now && now < $0.endsAt }) {
      let band = bands[index]
      switch band.kind {
      case .normal:
        let remaining = minutesBetween(from: now, to: band.endsAt)
        return RunStatusNow(
          caseKind: .ridingNormal(remainingMinutes: remaining, endsAt: band.endsAt),
          referencedNormalBand: band
        )
      case .dense, .hold:
        if let nextNormal = bands[(index + 1)...].first(where: { $0.kind == .normal }) {
          let until = minutesBetween(from: now, to: nextNormal.startsAt)
          let length = minutesBetween(from: nextNormal.startsAt, to: nextNormal.endsAt)
          return RunStatusNow(
            caseKind: .waitingForNormal(
              status: band.kind,
              minutesUntilNextNormal: until,
              nextNormalDurationMinutes: length
            ),
            referencedNormalBand: nextNormal
          )
        }
        return RunStatusNow(
          caseKind: .afterLastNormal(status: band.kind),
          referencedNormalBand: nil
        )
      }
    }

    return RunStatusNow(caseKind: .afterRangeEnd, referencedNormalBand: nil)
  }

  static func nextMarkers(
    now: Date,
    adoptedBlocks: [TimetableOpeningInterval]
  ) -> RunStatusNext {
    let valid = adoptedBlocks.filter { $0.endsAt > $0.startsAt && $0.endsAt > now }
      .sorted { $0.startsAt < $1.startsAt }

    let occupying = valid.filter { $0.startsAt <= now && now < $0.endsAt }
    if !occupying.isEmpty {
      let frontier = mergedOccupancyEnd(containing: now, blocks: valid)
      return RunStatusNext(
        currentBandEndsAt: frontier,
        nextStopInTarget: nil,
        nextRideInTarget: frontier
      )
    }

    let nextStart = valid.first { $0.startsAt > now }?.startsAt
    return RunStatusNext(
      currentBandEndsAt: nil,
      nextStopInTarget: nextStart,
      nextRideInTarget: nil
    )
  }

  static func formatHM(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    return "\(hours):\(String(format: "%02d", mins))"
  }

  private static func mergeAdopted(
    _ blocks: [TimetableOpeningInterval],
    lowerBound: Date,
    upperBound: Date
  ) -> [TimetableOpeningInterval] {
    let clipped = blocks
      .filter { $0.endsAt > $0.startsAt }
      .map { block -> TimetableOpeningInterval in
        TimetableOpeningInterval(
          startsAt: max(block.startsAt, lowerBound),
          endsAt: min(block.endsAt, upperBound)
        )
      }
      .filter { $0.endsAt > $0.startsAt }
      .sorted { $0.startsAt < $1.startsAt }

    var merged: [TimetableOpeningInterval] = []
    for block in clipped {
      if let last = merged.last, block.startsAt <= last.endsAt {
        merged[merged.count - 1].endsAt = max(last.endsAt, block.endsAt)
      } else {
        merged.append(block)
      }
    }
    return merged
  }

  private static func mergedOccupancyEnd(
    containing now: Date,
    blocks: [TimetableOpeningInterval]
  ) -> Date {
    var frontier = now
    var changed = true
    while changed {
      changed = false
      for block in blocks where block.startsAt <= frontier && block.endsAt > frontier {
        if block.endsAt > frontier {
          frontier = block.endsAt
          changed = true
        }
      }
    }
    return frontier
  }

  private static func minutesBetween(from: Date, to: Date) -> Int {
    max(0, Int(to.timeIntervalSince(from) / 60))
  }
}

private extension Array {
  subscript(safe index: Int) -> Element? {
    guard indices.contains(index) else { return nil }
    return self[index]
  }
}