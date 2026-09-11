import SwiftUI
import CoreImage.CIFilterBuiltins

struct CompanionQRCodeView: View {
    var encoded: String
    var dimension: CGFloat = 240

    var body: some View {
        Image(uiImage: render())
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: dimension, height: dimension)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: TrainTheme.Radius.control))
            .accessibilityLabel("Mac に向ける QR")
    }

    private func render() -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(encoded.utf8)
        filter.correctionLevel = "M"
        let transform = CGAffineTransform(scaleX: 10, y: 10)
        guard let output = filter.outputImage?.transformed(by: transform) else {
            return UIImage()
        }
        return UIImage(ciImage: output)
    }
}
