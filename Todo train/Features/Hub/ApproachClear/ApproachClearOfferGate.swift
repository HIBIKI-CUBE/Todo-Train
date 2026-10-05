//
//  ApproachClearOfferGate.swift
//  Todo train
//
//  Mounts the clearance only for a return after a long background.
//

import SwiftUI

struct ApproachClearOfferGate: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool

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
                offer.noteBackground(at: .now)
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
