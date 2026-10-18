import Foundation

public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

public enum SealSeed {
    public static func seed(rideID: UUID) -> UInt64 {
        withUnsafeBytes(of: rideID.uuid) { raw in
            let slice = raw.bindMemory(to: UInt8.self)
            var high: UInt64 = 0
            var low: UInt64 = 0
            for index in 0 ..< 8 {
                high = (high << 8) | UInt64(slice[index])
            }
            for index in 8 ..< 16 {
                low = (low << 8) | UInt64(slice[index])
            }
            return high ^ low
        }
    }
}

public enum SealDetail {
    case full
    case compact
}

public struct FukeiSealMetrics: Equatable, Sendable {
    public var frameSide: Double
    public var outerStroke: Double
    public var innerStroke: Double
    public var inset: Double
    public var innerHeight: Double
    public var pictureHeight: Double
    public var showsPicture: Bool
    public var skyGlyphSize: Double
    public var showsSkyGlyph: Bool
    public var seasonMarkAlpha: Double
    public var titleSize: Double
    public var dateSize: Double
    public var textBlockTop: Double
    public var inkOpacity: Double
    /// Mix rate toward pale vermilion: `(1 − L) × 0.5`. Color blending is on the drawing side.
    public var inkMix: Double
    public var lineWidthFloor: Double
}

public enum FukeiSealLayout {
    private static func clampLuxury(_ luxury: Double) -> Double {
        min(max(luxury, 0), 1)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }

    public static func metrics(luxury: Double) -> FukeiSealMetrics {
        let L = clampLuxury(luxury)
        let frameSide = lerp(0.67, 0.92, L)
        let outerStroke = lerp(0.020, 0.040, L)
        let innerStroke = L >= 0.95 ? 0.010 : 0
        let inset = 0.06 * frameSide
        let innerHeight = frameSide - 2 * inset
        let pictureHeight = 0.60 * L * innerHeight
        let showsPicture = pictureHeight >= 0.04
        let skyGlyphSize = min(0.12, 0.6 * pictureHeight)
        let showsSkyGlyph = pictureHeight >= 0.06
        let seasonMarkAlpha = clamp((0.30 - L) / 0.20, min: 0, max: 1)
        let titleSize = 0.20 * frameSide
        let dateSize = 0.08 * frameSide
        let textBlockHeight = titleSize + 0.02 + dateSize
        let textBlockTop: Double
        if showsPicture {
            textBlockTop = inset + pictureHeight + 0.03
        } else {
            textBlockTop = inset + (innerHeight - textBlockHeight) / 2
        }
        let inkOpacity = lerp(0.70, 1.00, L)
        let inkMix = (1 - L) * 0.5
        let lineWidthFloor = 0.012

        return FukeiSealMetrics(
            frameSide: frameSide,
            outerStroke: outerStroke,
            innerStroke: innerStroke,
            inset: inset,
            innerHeight: innerHeight,
            pictureHeight: pictureHeight,
            showsPicture: showsPicture,
            skyGlyphSize: skyGlyphSize,
            showsSkyGlyph: showsSkyGlyph,
            seasonMarkAlpha: seasonMarkAlpha,
            titleSize: titleSize,
            dateSize: dateSize,
            textBlockTop: textBlockTop,
            inkOpacity: inkOpacity,
            inkMix: inkMix,
            lineWidthFloor: lineWidthFloor
        )
    }
}

public struct SealWear: Equatable, Sendable {
    public struct Speck: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var radius: Double

        public init(x: Double, y: Double, radius: Double) {
            self.x = x
            self.y = y
            self.radius = radius
        }
    }

    public struct Chip: Equatable, Sendable {
        public var angle: Double
        public var size: Double

        public init(angle: Double, size: Double) {
            self.angle = angle
            self.size = size
        }
    }

    public var specks: [Speck]
    public var chips: [Chip]
    public var pressureAngle: Double
    public var pressureDepth: Double

    public static func make(seed: UInt64, luxury: Double, detail: SealDetail) -> SealWear {
        let L = min(max(luxury, 0), 1)
        let k = 1 - L
        var speckCount = Int(round(40 + 260 * k))
        if detail == .compact {
            speckCount = Int(round(Double(speckCount) * 0.15))
        }
        var chipCount = Int(round(1 + 5 * k))
        if detail == .compact {
            chipCount = 0
        }
        let pressureDepth = 0.10 + 0.25 * k

        var rng = SplitMix64(seed: seed)

        func unitDouble() -> Double {
            Double(rng.next() >> 11) / Double(1 << 53)
        }

        func uniform(_ low: Double, _ high: Double) -> Double {
            low + (high - low) * unitDouble()
        }

        var specks: [Speck] = []
        specks.reserveCapacity(speckCount)
        for _ in 0 ..< speckCount {
            let x = unitDouble()
            let y = unitDouble()
            let radius = uniform(0.004, 0.012)
            specks.append(Speck(x: x, y: y, radius: radius))
        }

        var chips: [Chip] = []
        chips.reserveCapacity(chipCount)
        for _ in 0 ..< chipCount {
            let angle = uniform(0, 2 * Double.pi)
            let size = uniform(0.02, 0.06)
            chips.append(Chip(angle: angle, size: size))
        }

        let pressureAngle = uniform(0, 2 * Double.pi)

        return SealWear(
            specks: specks,
            chips: chips,
            pressureAngle: pressureAngle,
            pressureDepth: pressureDepth
        )
    }
}
