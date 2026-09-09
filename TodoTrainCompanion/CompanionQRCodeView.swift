import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins

struct CompanionQRCodeView: View {
    var encoded: String
    var dimension: CGFloat = 280

    var body: some View {
        Image(nsImage: render())
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: dimension, height: dimension)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel("iPhone に向ける QR")
    }

    private func render() -> NSImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(encoded.utf8)
        filter.correctionLevel = "M"
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let output = filter.outputImage?.transformed(by: transform) else {
            return NSImage()
        }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
