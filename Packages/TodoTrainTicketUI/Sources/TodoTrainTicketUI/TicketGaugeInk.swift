import SwiftUI
#if os(iOS)
import UIKit
#endif

enum TicketGaugeInk {
    static var rail: Color { Color.accentColor }

    static var highlight: Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.35, green: 0.78, blue: 0.52, alpha: 1)
                : UIColor(red: 0.18, green: 0.55, blue: 0.38, alpha: 1)
        })
        #else
        Color(red: 0.18, green: 0.55, blue: 0.38)
        #endif
    }

    static var snap: Animation { .spring(response: 0.22, dampingFraction: 0.62) }
    static var soft: Animation { .easeInOut(duration: 0.28) }
}

extension View {
    @ViewBuilder
    func ticketGlass<S: InsettableShape>(_ tint: Color?, in shape: S) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else if let tint {
            self.background(tint.opacity(0.92), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }
}
