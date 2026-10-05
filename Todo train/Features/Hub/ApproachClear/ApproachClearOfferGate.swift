//
//  ApproachClearOfferGate.swift
//  Todo train
//
//  Mounts the clearance after five minutes away, except a mid-ride departure.
//

import SwiftUI

struct ApproachClearOfferGate: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool
    /// An open ride that is not paused. Leaving then does not earn the reward.
    var taskRunning: Bool

    @Environment(\.scenePhase) private var scenePhase
    @State private var offer = ApproachClearOfferStore.load()

    var body: some View {
        Group {
            if offer.showing {
                ApproachClearPanel(
                    world: world,
                    interactionsFrozen: interactionsFrozen,
                    onPlayStarted: {
                        offer.notePlayStarted()
                        ApproachClearOfferStore.save(offer)
                    },
                    onFinished: {
                        offer.dismiss()
                        ApproachClearOfferStore.save(offer)
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(TrainTheme.Motion.soft, value: offer.showing)
        .onAppear {
            if scenePhase == .active {
                noteActive()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                offer.noteBackground(at: .now, taskRunning: taskRunning)
                ApproachClearOfferStore.save(offer)
            case .active:
                noteActive()
            default:
                break
            }
        }
    }

    private func noteActive() {
        offer.noteActive(at: .now)
        ApproachClearOfferStore.save(offer)
    }
}
