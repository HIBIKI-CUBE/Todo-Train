//
//  DeleteConfirmation.swift
//  Todo train
//
//  Physical delete uses a centered alert (no undo). Swipe reveals the action;
//  the alert carries consequence copy from `TicketDeletion.Prompt`.
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

    /// Trailing destructive swipe. Full swipe is allowed — confirmation lives in the alert.
    func deleteSwipeAction(
        accessibilityName: String,
        action: @escaping () -> Void
    ) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("削除", role: .destructive, action: action)
                .accessibilityLabel("\(accessibilityName)を削除")
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
                onDelete(target)
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
