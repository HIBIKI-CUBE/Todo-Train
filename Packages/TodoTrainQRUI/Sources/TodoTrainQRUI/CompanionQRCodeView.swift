import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pairing QR chrome. Padding / corner / VoiceOver copy stay platform-specific at the call site.
public struct CompanionQRCodeView: View {
    public var encoded: String
    public var dimension: CGFloat
    public var chromePadding: CGFloat
    public var cornerRadius: CGFloat
    public var accessibilityLabelText: String

    public init(
        encoded: String,
        dimension: CGFloat = 220,
        chromePadding: CGFloat = 16,
        cornerRadius: CGFloat = 12,
        accessibilityLabel: String
    ) {
        self.encoded = encoded
        self.dimension = dimension
        self.chromePadding = chromePadding
        self.cornerRadius = cornerRadius
        self.accessibilityLabelText = accessibilityLabel
    }

    public var body: some View {
        Group {
            if let cgImage = CompanionQRCodeRenderer.makeCGImage(encoded: encoded) {
                qrImage(cgImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.white
            }
        }
        .frame(width: dimension, height: dimension)
        .padding(chromePadding)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityLabel(accessibilityLabelText)
    }

    @ViewBuilder
    private func qrImage(_ cgImage: CGImage) -> Image {
        #if canImport(UIKit)
        Image(uiImage: UIImage(cgImage: cgImage))
        #elseif canImport(AppKit)
        Image(nsImage: NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        ))
        #endif
    }
}
