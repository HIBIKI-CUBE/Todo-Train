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

    enum Layout {
        case automatic
        case horizontalScroll
        case flow
    }

    let minutesOptions: [Int]
    let style: Style
    let layout: Layout
    var highlightedMinutes: Int?
    var selectedMinutes: Int?
    let onSelect: (Int) -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    static let ticketPresets = [5, 10, 15, 20, 30, 45, 60]
    static let extendPresets = [5, 10, 15]

    init(
        minutesOptions: [Int] = EstimateChips.extendPresets,
        style: Style = .extendPrefix,
        layout: Layout = .automatic,
        highlightedMinutes: Int? = nil,
        selectedMinutes: Int? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.minutesOptions = minutesOptions
        self.style = style
        self.layout = layout
        self.highlightedMinutes = highlightedMinutes
        self.selectedMinutes = selectedMinutes
        self.onSelect = onSelect
    }

    private var resolvedLayout: Layout {
        switch layout {
        case .automatic:
            return verticalSizeClass == .compact ? .flow : .horizontalScroll
        case .horizontalScroll, .flow:
            return layout
        }
    }

    var body: some View {
        Group {
            switch resolvedLayout {
            case .horizontalScroll:
                horizontalChips
            case .flow:
                flowChips
            case .automatic:
                horizontalChips
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var horizontalChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(minutesOptions, id: \.self) { minutes in
                    chipButton(for: minutes)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var flowChips: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 52), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(minutesOptions, id: \.self) { minutes in
                chipButton(for: minutes)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func chipButton(for minutes: Int) -> some View {
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
