//
//  HistoryOutcomeBadge.swift
//  Todo train
//

import SwiftUI

struct HistoryOutcomeBadge: View {
    let outcome: SessionOutcome?
    let punctuality: ArrivalPunctuality

    init(outcome: SessionOutcome?, punctuality: ArrivalPunctuality) {
        self.outcome = outcome
        self.punctuality = punctuality
    }

    init(session: WorkSession) {
        outcome = session.outcome
        punctuality = Punctuality.classify(session)
    }

    var body: some View {
        switch outcome {
        case .arrived:
            switch punctuality {
            case .onTime:
                SignalBadge(kind: .onTime)
            case .early:
                SignalBadge(kind: .early)
            default:
                SignalBadge(kind: .arrived)
            }
        case .partialDisembark:
            SignalBadge(kind: .paused, customLabel: "途中下車")
        case .abandoned:
            SignalBadge(kind: .abandoned)
        default:
            Text(HistoryStats.outcomeLabel(outcome))
                .font(.caption.weight(.semibold))
                .foregroundStyle(TrainTheme.muted)
        }
    }
}
