//
//  TimetableBoardingConfirm.swift
//  Todo train
//
//  発車の重なり確認。拒否ではない。やめるは発車しないだけ。
//

import SwiftUI

extension View {
    func timetableBoardingConfirm(
        conflict: Binding<TimetableBoardingConflict?>,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            conflict.wrappedValue.map(TimetableCopy.conflictTitle) ?? "",
            isPresented: Binding(
                get: { conflict.wrappedValue != nil },
                set: { if !$0 { conflict.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(TimetableCopy.boardAnyway) {
                onConfirm()
                conflict.wrappedValue = nil
            }
            Button(TimetableCopy.cancelBoard, role: .cancel) {
                conflict.wrappedValue = nil
            }
        } message: {
            if let conflict = conflict.wrappedValue {
                Text(TimetableCopy.conflictMessage(conflict))
            }
        }
    }
}
