//
//  DeletionUndoCenter.swift
//  Todo train
//

import Foundation
import Observation

/// Holds the last deletion so the banner can restore it. A new delete replaces
/// the previous undo window (the earlier delete stays committed).
@Observable
@MainActor
final class DeletionUndoCenter {
    private(set) var bannerMessage: String?
    private var restore: (() -> Void)?
    private var hideTask: Task<Void, Never>?

    func offer(message: String, restore: @escaping () -> Void) {
        hideTask?.cancel()
        bannerMessage = message
        self.restore = restore
        hideTask = Task { [weak self] in
            let nanos = UInt64(DeletionUndo.bannerDurationSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    func undo() {
        hideTask?.cancel()
        let restore = self.restore
        commit()
        restore?()
    }

    func commit() {
        hideTask?.cancel()
        hideTask = nil
        bannerMessage = nil
        restore = nil
    }
}
