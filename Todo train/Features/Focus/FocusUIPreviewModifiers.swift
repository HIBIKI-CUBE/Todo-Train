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
                FocusUIPreview.requestLandscapeOrientationIfNeeded()
            }
            .task {
                guard FocusUIPreview.isActive, FocusUIPreview.wantsLandscape else { return }
                for _ in 0..<6 {
                    FocusUIPreview.requestLandscapeOrientationIfNeeded()
                    try? await Task.sleep(for: .milliseconds(350))
                }
            }
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
