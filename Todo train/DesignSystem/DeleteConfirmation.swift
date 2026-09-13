//
//  DeleteConfirmation.swift
//  Todo train
//
//  Physical delete is undoable, so swipe uses full swipe + destructive role
//  (HIG Alerts: no alert for common undoable deletes). The undo banner lives
//  on ContentView.
//

import SwiftUI

extension View {
    /// Trailing delete swipe. Full swipe is on because deletion can be undone.
    func deleteSwipeAction(
        accessibilityName: String,
        action: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: action) {
                Label("削除", systemImage: "trash")
            }
            .accessibilityLabel("\(accessibilityName)を削除")
        }
    }

    /// Second alert on a sibling view so it doesn't collide with other alerts.
    func errorAlert(isPresented: Binding<Bool>, message: String) -> some View {
        background {
            EmptyView()
                .alert("エラー", isPresented: isPresented) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(message)
                }
        }
    }
}

struct DeletionUndoBanner: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TrainTheme.Space.md) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer(minLength: TrainTheme.Space.sm)
            Button("取り消す", action: onUndo)
                .font(.subheadline.weight(.semibold))
                .tint(TrainTheme.rail)
        }
        .padding(.horizontal, TrainTheme.Space.lg)
        .padding(.vertical, TrainTheme.Space.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
