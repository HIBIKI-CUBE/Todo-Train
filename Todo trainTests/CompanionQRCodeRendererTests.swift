import CoreGraphics
import Testing
@testable import Todo_train

struct CompanionQRCodeRendererTests {
    @Test func pairingURLRendersSquareDarkModules() throws {
        let encoded = "todotrain://pair?p=a1a2a3a4-b1b2-4c3c-8d4d-e5e6e7e8e9ea&o=b1b2b3b4-c1c2-4d3d-8e4e-f5f6f7f8f9fb&x=6cUEjnLPwR0PtWYzHUVx7rfJ4kbso5tubUYqdeFHIRI"
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
