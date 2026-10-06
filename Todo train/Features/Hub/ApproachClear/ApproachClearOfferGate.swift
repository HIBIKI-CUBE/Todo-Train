//
//  ApproachClearOfferGate.swift
//  Todo train
//
//  Mounts the clearance after five minutes away, except a mid-ride departure.
//  The developer menu can force it on without spending that reward.
//

import SwiftUI

struct ApproachClearOfferGate: View {
    var world: ApproachClearWorld
    var interactionsFrozen: Bool
    /// An open ride that is not paused. Leaving then does not earn the reward.
    var taskRunning: Bool

    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSettings.self) private var settings
    @State private var offer = ApproachClearOfferStore.load()
    @State private var debugReplay = 0

    private var forced: Bool {
        settings.developerToolsUnlocked && settings.forceApproachClearVisible
    }

    private var presented: Bool {
        ApproachClearVisibility.presented(
            offerShowing: offer.showing,
            developerToolsUnlocked: settings.developerToolsUnlocked,
            forceVisible: settings.forceApproachClearVisible
        )
    }

    var body: some View {
        Group {
            if presented {
                ApproachClearPanel(
                    world: world,
                    interactionsFrozen: interactionsFrozen,
                    onPlayStarted: {
                        guard !forced else { return }
                        offer.notePlayStarted()
                        ApproachClearOfferStore.save(offer)
                    },
                    onFinished: {
                        if forced {
                            debugReplay += 1
                        } else {
                            offer.dismiss()
                            ApproachClearOfferStore.save(offer)
                        }
                    }
                )
                .id(debugReplay)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(TrainTheme.Motion.soft, value: presented)
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
