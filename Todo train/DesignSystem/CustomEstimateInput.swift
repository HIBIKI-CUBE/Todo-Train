//
//  CustomEstimateInput.swift
//  Todo train
//

import SwiftUI

enum CustomEstimate {
    static let minMinutes = 1
    static let maxMinutes = 60

    static func clampMinutes(_ value: Int) -> Int {
        min(max(value, minMinutes), maxMinutes)
    }

    static func parseMinutes(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return nil }
        guard (minMinutes...maxMinutes).contains(value) else { return nil }
        return value
    }
}

struct CustomEstimateInput: View {
    @Binding var minutes: Int
    var highlightedMinutes: Int?

    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("分（1–60）", text: $text)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: text) { _, newValue in
                        if let parsed = CustomEstimate.parseMinutes(from: newValue) {
                            minutes = parsed
                        }
                    }

                Stepper("", value: Binding(
                    get: { minutes },
                    set: { minutes = CustomEstimate.clampMinutes($0) }
                ), in: CustomEstimate.minMinutes...CustomEstimate.maxMinutes)
                .labelsHidden()
            }

            Text("現在 \(minutes) 分")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let highlightedMinutes, highlightedMinutes != minutes {
                Text("ヒント: 過去の中央値は約 \(highlightedMinutes) 分")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            text = "\(minutes)"
        }
        .onChange(of: minutes) { _, newValue in
            let clamped = CustomEstimate.clampMinutes(newValue)
            if clamped != newValue {
                minutes = clamped
            }
            text = "\(minutes)"
        }
    }
}
