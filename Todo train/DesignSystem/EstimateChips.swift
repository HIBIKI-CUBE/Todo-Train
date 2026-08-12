//
//  EstimateChips.swift
//  Todo train
//

import SwiftUI

struct EstimateChips: View {
    enum Style {
        case extendPrefix   // "+5分"
        case plainMinutes   // "5分"
    }

    let minutesOptions: [Int]
    let style: Style
    var highlightedMinutes: Int?
    var selectedMinutes: Int?
    let onSelect: (Int) -> Void

    static let ticketPresets = [5, 10, 15, 20, 30, 45, 60]
    static let extendPresets = [5, 10, 15]

    init(
        minutesOptions: [Int] = EstimateChips.extendPresets,
        style: Style = .extendPrefix,
        highlightedMinutes: Int? = nil,
        selectedMinutes: Int? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.minutesOptions = minutesOptions
        self.style = style
        self.highlightedMinutes = highlightedMinutes
        self.selectedMinutes = selectedMinutes
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(minutesOptions, id: \.self) { minutes in
                    let selected = selectedMinutes == minutes
                    let suggested = highlightedMinutes == minutes && !selected
                    let label: String = {
                        switch style {
                        case .extendPrefix: "+\(minutes)分"
                        case .plainMinutes: "\(minutes)分"
                        }
                    }()

                    Button {
                        onSelect(minutes)
                    } label: {
                        Text(label)
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? TrainTheme.rail : (suggested ? TrainTheme.signalGreen : .secondary))
                    .fontWeight(selected || suggested ? .semibold : .regular)
                }
            }
            .padding(.vertical, 2)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}
