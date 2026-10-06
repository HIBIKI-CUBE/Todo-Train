//
//  ApproachClearOfferTests.swift
//  Todo trainTests
//

import Foundation
import Testing
@testable import Todo_train

struct ApproachClearOfferTests {
    @Test func staysHiddenUntilTheAppHasBeenAway() {
        var offer = ApproachClearOffer()
        let start = Date(timeIntervalSince1970: 0)
        offer.noteActive(at: start)
        #expect(!offer.showing)

        offer.noteBackground(at: start)
        offer.noteActive(at: start.addingTimeInterval(ApproachClearOffer.absence - 60))
        #expect(!offer.showing)

        let left = start.addingTimeInterval(ApproachClearOffer.absence - 60)
        offer.noteBackground(at: left)
        offer.noteActive(at: left.addingTimeInterval(ApproachClearOffer.absence))
        #expect(offer.showing)
        #expect(!offer.spent)
    }

    @Test func anUnplayedOfferSurvivesAShortInterruption() {
        var offer = ApproachClearOffer()
        let start = Date(timeIntervalSince1970: 10_000)
        offer.noteBackground(at: start)
        offer.noteActive(at: start.addingTimeInterval(ApproachClearOffer.absence))
        #expect(offer.showing)

        let back = start.addingTimeInterval(ApproachClearOffer.absence)
        offer.noteBackground(at: back.addingTimeInterval(20))
        offer.noteActive(at: back.addingTimeInterval(40))
        #expect(offer.showing)
        #expect(!offer.spent)
    }

    @Test func onePlayDoesNotReturnUntilTheNextLongAbsence() {
        var offer = ApproachClearOffer()
        let start = Date(timeIntervalSince1970: 20_000)
        offer.noteBackground(at: start)
        let opened = start.addingTimeInterval(ApproachClearOffer.absence)
        offer.noteActive(at: opened)
        offer.notePlayStarted()
        offer.dismiss()
        #expect(!offer.showing)
        #expect(offer.spent)

        offer.noteBackground(at: opened.addingTimeInterval(10))
        offer.noteActive(at: opened.addingTimeInterval(40))
        #expect(!offer.showing)

        let left = opened.addingTimeInterval(40)
        offer.noteBackground(at: left)
        offer.noteActive(at: left.addingTimeInterval(ApproachClearOffer.absence))
        #expect(offer.showing)
        #expect(!offer.spent)
    }

    @Test func aStartedPlayDoesNotSurviveAShortRelaunch() {
        var offer = ApproachClearOffer()
        let start = Date(timeIntervalSince1970: 30_000)
        offer.noteBackground(at: start)
        let opened = start.addingTimeInterval(ApproachClearOffer.absence)
        offer.noteActive(at: opened)
        offer.notePlayStarted()
        #expect(offer.showing)

        offer.noteBackground(at: opened.addingTimeInterval(5))
        offer.noteActive(at: opened.addingTimeInterval(20))
        #expect(!offer.showing)
        #expect(offer.spent)
    }

    @Test func leavingDuringATaskDoesNotCount() {
        var offer = ApproachClearOffer()
        let start = Date(timeIntervalSince1970: 40_000)
        offer.noteBackground(at: start, taskRunning: true)
        offer.noteActive(at: start.addingTimeInterval(ApproachClearOffer.absence))
        #expect(!offer.showing)

        let back = start.addingTimeInterval(ApproachClearOffer.absence)
        offer.noteBackground(at: back)
        offer.noteActive(at: back.addingTimeInterval(ApproachClearOffer.absence))
        #expect(offer.showing)
        #expect(!offer.spent)
    }

    @Test func forceVisibleNeedsTheDeveloperMenu() {
        #expect(!ApproachClearVisibility.presented(
            offerShowing: false,
            developerToolsUnlocked: false,
            forceVisible: true
        ))
        #expect(!ApproachClearVisibility.presented(
            offerShowing: false,
            developerToolsUnlocked: true,
            forceVisible: false
        ))
        #expect(ApproachClearVisibility.presented(
            offerShowing: false,
            developerToolsUnlocked: true,
            forceVisible: true
        ))
        #expect(ApproachClearVisibility.presented(
            offerShowing: true,
            developerToolsUnlocked: false,
            forceVisible: false
        ))
    }

    @Test func storeRoundTrip() {
        let name = "ApproachClearOfferTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        var offer = ApproachClearOffer()
        offer.noteBackground(at: Date(timeIntervalSince1970: 50), taskRunning: true)
        offer.showing = true
        offer.spent = true
        ApproachClearOfferStore.save(offer, defaults)
        #expect(ApproachClearOfferStore.load(defaults) == offer)
        defaults.removePersistentDomain(forName: name)
    }
}
