//
//  DeleteConfirmation.swift
//  Todo train
//
//  Physical delete follows HIG Alerts + swipeActions:
//  - No undo, so no full swipe (swipe + tap is the two-step confirm).
//  - Alert only when the tap would do more than the row implies.
//  - Don't use `role: .destructive` on a swipe that merely presents an alert
//    (the row animates out, the alert can vanish, then the row snaps back).
//  - `Label("削除", systemImage: "trash")` so short rows get the system icon.
//  - One `.alert` per view; errors attach to a sibling via `errorAlert`.
//

import SwiftUI

extension View {
    /// Presents a destructive alert for the currently pending item.
    /// Set `item` to present; clearing it (cancel or confirm) dismisses.
    func deletionAlert<Item>(
        item: Binding<Item?>,
        prompt: @escaping (Item) -> TicketDeletion.Prompt,
        onDelete: @escaping (Item) -> Void
    ) -> some View {
        modifier(
            DeletionAlertModifier(
                item: item,
                prompt: prompt,
                onDelete: onDelete
            )
        )
    }

    /// Trailing delete swipe. Full swipe is off (no undo).
    /// - Parameter needsConfirmation: If true, the button only queues an alert
    ///   and must not use the destructive role (avoids the snap-back).
    func deleteSwipeAction(
        accessibilityName: String,
        needsConfirmation: Bool,
        action: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if needsConfirmation {
                Button(action: action) {
                    Label("削除", systemImage: "trash")
                }
                .tint(.red)
                .accessibilityLabel("\(accessibilityName)を削除")
            } else {
                Button(role: .destructive, action: action) {
                    Label("削除", systemImage: "trash")
                }
                .accessibilityLabel("\(accessibilityName)を削除")
            }
        }
    }

    /// Second alert on a sibling view so it doesn't replace `deletionAlert`.
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

private struct DeletionAlertModifier<Item>: ViewModifier {
    @Binding var item: Item?
    let prompt: (Item) -> TicketDeletion.Prompt
    let onDelete: (Item) -> Void

    func body(content: Content) -> some View {
        content.alert(
            currentTitle,
            isPresented: isPresented,
            presenting: item
        ) { presented in
            Button("削除", role: .destructive) {
                let target = presented
                item = nil
                withAnimation {
                    onDelete(target)
                }
            }
            Button("キャンセル", role: .cancel) {
                item = nil
            }
        } message: { presented in
            Text(prompt(presented).message)
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { item != nil },
            set: { if !$0 { item = nil } }
        )
    }

    private var currentTitle: String {
        item.map { prompt($0).title } ?? "削除しますか？"
    }
}
