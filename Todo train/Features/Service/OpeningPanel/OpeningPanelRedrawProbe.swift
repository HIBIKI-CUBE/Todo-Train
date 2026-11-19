//
//  OpeningPanelRedrawProbe.swift
//  Todo train
//
//  盤の body が何回走ったかを数える。計測のときだけ点ける。
//

import Foundation

@MainActor
enum OpeningPanelRedrawProbe {
    static var enabled = false
    /// 点いているあいだ、`changes`（`Self._printChanges()`）を呼ぶ。
    static var trace = false
    private(set) static var counts: [String: Int] = [:]

    static func bump(_ name: String, _ changes: () -> Void = {}) {
        guard enabled else { return }
        counts[name, default: 0] += 1
        if trace {
            print("TRACE \(name)")
            changes()
        }
    }

    static func reset() {
        counts.removeAll(keepingCapacity: true)
    }

    static func snapshot() -> [String: Int] {
        counts
    }
}
