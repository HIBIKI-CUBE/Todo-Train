import Foundation
import Testing
@testable import TodoTrainSync

@Suite("Seal geometry")
struct SealGeometryTests {
    private func expectClose(_ actual: Double, _ expected: Double) {
        #expect(abs(actual - expected) < 1e-9)
    }

    @Test func splitMix64_firstThreeValues_seed0() {
        var rng = SplitMix64(seed: 0)
        #expect(rng.next() == 16_294_208_416_658_607_535)
        #expect(rng.next() == 7_960_286_522_194_355_700)
        #expect(rng.next() == 487_617_019_471_545_679)
    }

    @Test func splitMix64_firstThreeValues_seed1() {
        var rng = SplitMix64(seed: 1)
        #expect(rng.next() == 10_451_216_379_200_822_465)
        #expect(rng.next() == 13_757_245_211_066_428_519)
        #expect(rng.next() == 17_911_839_290_282_890_590)
    }

    @Test func sealSeed_fixedUUID() {
        let rideID = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
        let first = SealSeed.seed(rideID: rideID)
        let second = SealSeed.seed(rideID: rideID)
        #expect(first == 8_493_206_004_548_380_421)
        #expect(second == first)
    }

    @Test func fukeiSealLayout_metricsAtLuxuryZero() {
        let m = FukeiSealLayout.metrics(luxury: 0)
        #expect(m.frameSide == 0.67)
        #expect(m.outerStroke == 0.02)
        #expect(m.innerStroke == 0)
        #expect(m.inset == 0.0402)
        #expect(m.innerHeight == 0.5896)
        #expect(m.pictureHeight == 0)
        #expect(m.showsPicture == false)
        #expect(m.skyGlyphSize == 0)
        #expect(m.showsSkyGlyph == false)
        #expect(m.seasonMarkAlpha == 1)
        #expect(m.titleSize == 0.134)
        #expect(m.dateSize == 0.0536)
        expectClose(m.textBlockTop, 0.23120000000000002)
        #expect(m.inkOpacity == 0.7)
        #expect(m.inkMix == 0.5)
        #expect(m.lineWidthFloor == 0.012)
    }

    @Test func fukeiSealLayout_metricsAtLuxuryHalf() {
        let m = FukeiSealLayout.metrics(luxury: 0.5)
        #expect(m.frameSide == 0.795)
        #expect(m.outerStroke == 0.03)
        #expect(m.innerStroke == 0)
        #expect(m.inset == 0.0477)
        #expect(m.innerHeight == 0.6996)
        expectClose(m.pictureHeight, 0.20987999999999998)
        #expect(m.showsPicture == true)
        #expect(m.skyGlyphSize == 0.12)
        #expect(m.showsSkyGlyph == true)
        #expect(m.seasonMarkAlpha == 0)
        expectClose(m.titleSize, 0.15900000000000003)
        #expect(m.dateSize == 0.0636)
        expectClose(m.textBlockTop, 0.28757999999999995)
        #expect(m.inkOpacity == 0.85)
        #expect(m.inkMix == 0.25)
        #expect(m.lineWidthFloor == 0.012)
    }

    @Test func fukeiSealLayout_metricsAtLuxury09() {
        let m = FukeiSealLayout.metrics(luxury: 0.9)
        #expect(m.frameSide == 0.895)
        expectClose(m.outerStroke, 0.038000000000000006)
        #expect(m.innerStroke == 0)
        #expect(m.inset == 0.0537)
        expectClose(m.innerHeight, 0.7876000000000001)
        expectClose(m.pictureHeight, 0.42530400000000007)
        #expect(m.showsPicture == true)
        #expect(m.skyGlyphSize == 0.12)
        #expect(m.showsSkyGlyph == true)
        #expect(m.seasonMarkAlpha == 0)
        expectClose(m.titleSize, 0.17900000000000002)
        #expect(m.dateSize == 0.0716)
        expectClose(m.textBlockTop, 0.5090040000000001)
        #expect(m.inkOpacity == 0.97)
        expectClose(m.inkMix, 0.04999999999999999)
        #expect(m.lineWidthFloor == 0.012)
    }

    @Test func fukeiSealLayout_metricsAtLuxuryOne() {
        let m = FukeiSealLayout.metrics(luxury: 1)
        #expect(m.frameSide == 0.92)
        #expect(m.outerStroke == 0.04)
        #expect(m.innerStroke == 0.01)
        #expect(m.inset == 0.0552)
        expectClose(m.innerHeight, 0.8096000000000001)
        #expect(m.pictureHeight == 0.48576)
        #expect(m.showsPicture == true)
        #expect(m.skyGlyphSize == 0.12)
        #expect(m.showsSkyGlyph == true)
        #expect(m.seasonMarkAlpha == 0)
        expectClose(m.titleSize, 0.18400000000000002)
        #expect(m.dateSize == 0.0736)
        #expect(m.textBlockTop == 0.57096)
        #expect(m.inkOpacity == 1)
        #expect(m.inkMix == 0)
        #expect(m.lineWidthFloor == 0.012)
    }

    @Test func fukeiSealLayout_pictureHeightAndInkOpacityIncreaseWithLuxury() {
        let samples = [0, 0.25, 0.5, 0.75, 1.0]
        var previousPicture: Double = -1
        var previousOpacity: Double = -1
        for L in samples {
            let m = FukeiSealLayout.metrics(luxury: L)
            #expect(m.pictureHeight >= previousPicture)
            #expect(m.inkOpacity >= previousOpacity)
            previousPicture = m.pictureHeight
            previousOpacity = m.inkOpacity
        }
    }

    @Test func fukeiSealLayout_innerStrokeOnlyAtTopLuxury() {
        #expect(FukeiSealLayout.metrics(luxury: 0.94).innerStroke == 0)
        #expect(FukeiSealLayout.metrics(luxury: 0.95).innerStroke == 0.01)
        #expect(FukeiSealLayout.metrics(luxury: 1).innerStroke == 0.01)
    }

    @Test func fukeiSealLayout_clampsLuxuryOutsideUnitInterval() {
        let low = FukeiSealLayout.metrics(luxury: -1)
        let zero = FukeiSealLayout.metrics(luxury: 0)
        let high = FukeiSealLayout.metrics(luxury: 2)
        let one = FukeiSealLayout.metrics(luxury: 1)
        #expect(low == zero)
        #expect(high == one)
    }

    @Test func fukeiSealLayout_showsPictureAtHalfNotAtZero() {
        #expect(FukeiSealLayout.metrics(luxury: 0.5).showsPicture == true)
        #expect(FukeiSealLayout.metrics(luxury: 0).showsPicture == false)
    }

    @Test func fukeiSealLayout_seasonMarkAlphaAtLowLuxury() {
        expectClose(FukeiSealLayout.metrics(luxury: 0.1).seasonMarkAlpha, 1)
        #expect(FukeiSealLayout.metrics(luxury: 0.3).seasonMarkAlpha == 0)
    }

    @Test func sealWear_sameSeedAndLuxuryIsDeterministic() {
        let a = SealWear.make(seed: 99, luxury: 0.8, detail: .full)
        let b = SealWear.make(seed: 99, luxury: 0.8, detail: .full)
        #expect(a == b)
        #expect(a.pressureAngle == 4.876908233222546)
        #expect(a.pressureDepth == 0.15)
        #expect(a.chips.count == 2)
        #expect(a.chips[0].angle == 5.950488063060019)
        #expect(a.chips[0].size == 0.0503462919236649)
    }

    @Test func sealWear_lowerLuxuryIncreasesSpeckAndChipCounts() {
        let rich = SealWear.make(seed: 7, luxury: 1, detail: .full)
        let worn = SealWear.make(seed: 7, luxury: 0, detail: .full)
        #expect(worn.specks.count > rich.specks.count)
        #expect(worn.chips.count > rich.chips.count)
        #expect(rich.specks.count == 40)
        #expect(rich.chips.count == 1)
        #expect(worn.specks.count == 300)
        #expect(worn.chips.count == 6)
    }

    @Test func sealWear_compactHasNoChipsAndFewerSpecks() {
        let full = SealWear.make(seed: 42, luxury: 0.5, detail: .full)
        let compact = SealWear.make(seed: 42, luxury: 0.5, detail: .compact)
        #expect(full.chips.count == 4)
        #expect(compact.chips.isEmpty)
        #expect(compact.specks.count == 26)
        #expect(full.specks.count == 170)
    }

    @Test func sealWear_firstSpeckStableWhenLuxuryChangesSpeckCount() {
        let mid = SealWear.make(seed: 42, luxury: 0.5, detail: .full)
        let moreWear = SealWear.make(seed: 42, luxury: 0.2, detail: .full)
        #expect(mid.specks.count != moreWear.specks.count)
        #expect(mid.specks[0] == moreWear.specks[0])
        #expect(mid.specks[0].x == 0.7415648787718233)
        #expect(mid.specks[0].y == 0.1599103928769201)
        #expect(mid.specks[0].radius == 0.006228809042041109)
    }
}
