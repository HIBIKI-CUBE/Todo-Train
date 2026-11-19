//
//  OpeningPanelRedrawProbe.swift
//  Todo train
//
//  盤の body が何回走ったかを数える。計測のときだけ点ける。
//

import Foundation

enum OpeningPanelRedrawProbe {
    static var enabled = false
    /// 点いているあいだ、`changes`（`Self._printChanges()`）を呼ぶ。
    static var trace = false
    private static let lock = NSLock()
    private static var storage: [String: Int] = [:]

    static func bump(_ name: String, _ changes: () -> Void = {}) {
        guard enabled else { return }
        lock.lock()
        storage[name, default: 0] += 1
        let tracing = trace
        lock.unlock()
        if tracing {
            print("TRACE \(name)")
            changes()
        }
    }

    static func reset() {
        lock.lock()
        storage.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    static func snapshot() -> [String: Int] {
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }
}
