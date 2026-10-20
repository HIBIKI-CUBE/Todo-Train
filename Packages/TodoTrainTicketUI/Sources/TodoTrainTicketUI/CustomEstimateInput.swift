//
//  CustomEstimateInput.swift
//  Todo train
//

import SwiftUI

public enum CustomEstimate {
    public static let minMinutes = 1
    public static let maxMinutes = 60

    public static func clampMinutes(_ value: Int) -> Int {
        min(max(value, minMinutes), maxMinutes)
    }

    public static func parseMinutes(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed) else { return nil }
        guard (minMinutes...maxMinutes).contains(value) else { return nil }
        return value
    }
}

public struct CustomEstimateInput: View {
    @Binding var minutes: Int
    public var highlightedMinutes: Int?

    public init(minutes: Binding<Int>, highlightedMinutes: Int? = nil) {
        _minutes = minutes
        self.highlightedMinutes = highlightedMinutes
    }

    @State private var text = ""

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("分（1–60）", text: $text)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
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
