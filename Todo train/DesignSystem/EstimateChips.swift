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
    let onSelect: (Int) -> Void

    static let ticketPresets = [5, 10, 15, 20, 30, 45, 60]
    static let extendPresets = [5, 10, 15]

    init(
        minutesOptions: [Int] = EstimateChips.extendPresets,
        style: Style = .extendPrefix,
        highlightedMinutes: Int? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.minutesOptions = minutesOptions
        self.style = style
        self.highlightedMinutes = highlightedMinutes
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(minutesOptions, id: \.self) { minutes in
                    let highlighted = highlightedMinutes == minutes
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(highlighted ? .white : TrainTheme.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                                    .fill(highlighted ? TrainTheme.rail : Color.white.opacity(0.9))
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: TrainTheme.Radius.control)
                                    .strokeBorder(
                                        highlighted ? Color.clear : TrainTheme.track,
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
