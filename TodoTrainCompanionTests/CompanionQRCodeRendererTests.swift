import CoreGraphics
import Testing
@testable import TodoTrainCompanion

struct CompanionQRCodeRendererTests {
    @Test func pairingURLRendersSquareDarkModules() throws {
        let encoded = "todotrain://pair-mac?s=c1c2c3c4-d1d2-4e3e-8f4f-a5a6a7a8a9aa&y=UgKyT75SOaUjcnm8rdNOZvC3qC3oVkNtdt-WlgkO9rI"
        let image = try #require(CompanionQRCodeRenderer.makeCGImage(encoded: encoded))
        #expect(image.width > 40)
        #expect(image.height == image.width)
        #expect(qrImageHasDarkModules(image))
    }
}

func qrImageHasDarkModules(_ image: CGImage) -> Bool {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return false
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    for index in stride(from: 0, to: pixels.count, by: 4) {
        if pixels[index] < 128, pixels[index + 1] < 128, pixels[index + 2] < 128 {
            return true
        }
    }
    return false
}
