//
//  RunStatusReferencedBandHighlight.swift
//  Todo train
//
//  参照している平常運転の帯を、運転状況の列で強調するときの見え方。
//

import SwiftUI

struct RunStatusBandIdentity: Equatable, Sendable {
    var startsAt: Date
    var endsAt: Date

    init(_ band: RunStatusBand) {
        startsAt = band.startsAt
        endsAt = band.endsAt
    }
}

extension RunStatusNow {
    /// いまの言い方が参照している平常運転。なければ強調しない。
    var referencedBandIdentity: RunStatusBandIdentity? {
        referencedNormalBand.map(RunStatusBandIdentity.init)
    }
}

extension RunStatusBand {
    func isReferenced(by reading: RunStatusNow) -> Bool {
        guard let identity = reading.referencedBandIdentity else { return false }
        return identity.startsAt == startsAt && identity.endsAt == endsAt
    }

    func isPast(relativeTo now: Date) -> Bool {
        now >= endsAt
    }
}

struct RunStatusReferencedBandHighlight: ViewModifier {
    var isReferenced: Bool
    var isPast: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isPast && !isReferenced ? OpeningPanelTokens.RunStatusChrome.pastBandOpacity : 1)
            .background {
                if isReferenced {
                    referencedBackground
                }
            }
            .overlay {
                if isReferenced {
                    referencedBorder
                } else if isPast {
                    EmptyView()
                }
            }
    }

  private var referencedBackground: some View {
    ZStack(alignment: .leading) {
      Rectangle()
        .fill(OpeningPanelTokens.RunStatusChrome.referencedBandFill)
      Rectangle()
        .fill(OpeningPanelTokens.RunStatusChrome.referenceAccent)
        .frame(width: OpeningPanelTokens.RunStatusChrome.referenceBarWidth)
    }
  }

  private var referencedBorder: some View {
    Rectangle()
      .strokeBorder(OpeningPanelTokens.RunStatusChrome.referenceAccent, lineWidth: 1)
  }
}

extension View {
    func runStatusReferencedBandHighlight(
        band: RunStatusBand,
        now: Date,
        reading: RunStatusNow
    ) -> some View {
        modifier(
            RunStatusReferencedBandHighlight(
                isReferenced: band.isReferenced(by: reading),
                isPast: band.isPast(relativeTo: now)
            )
        )
    }
}