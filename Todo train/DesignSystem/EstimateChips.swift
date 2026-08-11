//
//  EstimateChips.swift
//  Todo train
//

import SwiftUI

struct EstimateChips: View {
    let minutesOptions: [Int]
    let onSelect: (Int) -> Void

    init(minutesOptions: [Int] = [5, 10, 15], onSelect: @escaping (Int) -> Void) {
        self.minutesOptions = minutesOptions
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(minutesOptions, id: \.self) { minutes in
                Button("+\(minutes)分") {
                    onSelect(minutes)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
