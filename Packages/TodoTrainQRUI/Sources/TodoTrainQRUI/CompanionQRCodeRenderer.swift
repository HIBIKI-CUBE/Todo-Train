import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

public enum CompanionQRCodeRenderer {
    public static func makeCGImage(encoded: String, moduleScale: CGFloat = 10) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(encoded.utf8)
        filter.correctionLevel = "M"
        guard let raw = filter.outputImage else { return nil }
        let scaled = raw.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1)).cropped(to: scaled.extent)
        let opaque = scaled.composited(over: white)
        let context = CIContext(options: [
            .useSoftwareRenderer: true,
            .workingColorSpace: NSNull(),
        ])
        return context.createCGImage(opaque, from: opaque.extent)
    }
}
