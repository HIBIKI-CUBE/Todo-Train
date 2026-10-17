//
//  FocusUIPreviewModifiers.swift
//  Todo train
//

import SwiftUI
import UIKit

#if DEBUG
private struct FocusUIPreviewLandscapeOrientation: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                guard FocusUIPreview.isActive, FocusUIPreview.wantsLandscape else { return }
                requestLandscape()
            }
    }

    private func requestLandscape() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive || $0.activationState == .foregroundInactive })
            ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
    }
}

extension View {
    func focusUIPreviewOrientation() -> some View {
        modifier(FocusUIPreviewLandscapeOrientation())
    }
}
#endif
