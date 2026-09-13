import SwiftUI

/// Square QR finder corners. A wide rounded rect reads as a barcode window.
struct QRViewfinderFrame: View {
    var color: Color
    var lineWidth: CGFloat = 4
    var armRatio: CGFloat = 0.2

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let origin = CGPoint(
                x: (proxy.size.width - side) / 2,
                y: (proxy.size.height - side) / 2
            )
            let arm = max(20, side * armRatio)
            let rect = CGRect(x: origin.x, y: origin.y, width: side, height: side)
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

                path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

                path.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
                path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))

                path.move(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
            }
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .square, lineJoin: .miter))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
