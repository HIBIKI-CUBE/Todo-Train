//
//  ArrivalDeck.swift
//  Todo train
//
//  到着画面の行き先。検札は締めだけで、発車は別の操作。
//

import CoreGraphics
import Foundation

struct ArrivalTicketFace: Equatable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var minutes: Int
}

struct ArrivalDestination: Equatable, Sendable {
    var action: ArrivalAction
    var face: ArrivalTicketFace
}

/// 到着画面の中だけで持つ選択。ピッカーを閉じても到着画面は閉じない。
struct ArrivalDeck: Equatable, Sendable {
    enum Picker: Equatable, Sendable {
        case otherTickets
        case instant
    }

    var reserved: ArrivalTicketFace?
    var destination: ArrivalDestination?
    var picker: Picker?
    /// 検札後。この時点ではまだ発車していない。
    var stampedFace: ArrivalTicketFace?

    init(reserved: ArrivalTicketFace?) {
        self.reserved = reserved
        if let reserved {
            destination = ArrivalDestination(action: .nextRide, face: reserved)
        }
    }

    var canStamp: Bool {
        stampedFace == nil && picker == nil && destination != nil
    }

    mutating func showOtherTickets() {
        guard stampedFace == nil else { return }
        picker = .otherTickets
    }

    mutating func showInstant() {
        guard stampedFace == nil else { return }
        picker = .instant
    }

    /// 一覧や入力欄だけを閉じる。到着画面は残る。
    mutating func dismissPicker() {
        picker = nil
    }

    mutating func selectNextRide() {
        guard stampedFace == nil, let reserved else { return }
        destination = ArrivalDestination(action: .nextRide, face: reserved)
        picker = nil
    }

    mutating func selectOther(_ face: ArrivalTicketFace) {
        guard stampedFace == nil, face.id != reserved?.id else { return }
        destination = ArrivalDestination(action: .otherTicket, face: face)
        picker = nil
    }

    mutating func selectInstant(_ face: ArrivalTicketFace) {
        guard stampedFace == nil else { return }
        destination = ArrivalDestination(action: .instantTicket, face: face)
        picker = nil
    }

    /// 検札できるときだけ行き先を返す。発車はしない。
    func stampSelection() -> ArrivalDestination? {
        guard canStamp else { return nil }
        return destination
    }

    mutating func markStamped() {
        guard let destination else { return }
        stampedFace = destination.face
        picker = nil
    }

    /// 画面を開いたときに予約を読み直す。別の切符・即時切符を選んだあとは行き先を上書きしない。
    mutating func adoptReservation(_ face: ArrivalTicketFace?) {
        guard stampedFace == nil else { return }
        reserved = face
        switch destination?.action {
        case .otherTicket, .instantTicket:
            return
        case .nextRide, nil:
            if let face {
                destination = ArrivalDestination(action: .nextRide, face: face)
            } else {
                destination = nil
            }
        }
    }

    /// 指を止めて離しても、leading にこの距離まで動かせば発車する。Hub のフリック閾値は使わない。
    static let boardDistance: CGFloat = 96

    /// 検札後の券面で、leading のスワイプが発車の距離を超えたときだけ切符 id を返す。
    func boardTicketID(
        translation: CGSize,
        predictedEnd: CGSize,
        leadingIsPositiveX: Bool
    ) -> UUID? {
        _ = predictedEnd
        guard let stampedFace else { return nil }
        let width = TicketStackLayout.leadingWidth(
            translationWidth: translation.width,
            leadingIsPositiveX: leadingIsPositiveX
        )
        guard width >= Self.boardDistance, width > abs(translation.height) else { return nil }
        return stampedFace.id
    }
}
