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

    func focusUIPreviewQuickAddSheet() -> some View {
        modifier(FocusUIPreviewQuickAddSheet())
    }
}

private struct FocusUIPreviewQuickAddSheet: ViewModifier {
    @State private var presented = FocusUIPreview.parsedState() == "quickAdd"

    func body(content: Content) -> some View {
        content.sheet(isPresented: $presented) {
            QuickAddSheet(onSingleIssued: nil)
        }
    }
}
#endif
