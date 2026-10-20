//
//  DeveloperForecastLogView.swift
//  Todo train
//
//  Hidden Settings surface. Not part of the everyday product.
//

import SwiftUI

struct DeveloperForecastLogView: View {
    @Environment(ArrivalForecastTraceLog.self) private var log
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        List {
            if log.traces.isEmpty {
                Text("まだ予測の実行がありません。Hub で切符を持ち上げるとここに残ります。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(log.traces) { trace in
                    NavigationLink {
                        DeveloperForecastTraceView(trace: trace)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trace.title.isEmpty ? "（無題）" : trace.title)
                                .lineLimit(1)
                            HStack {
                                Text(trace.outcome.displayLabel)
                                Spacer()
                                if let minutes = trace.clampedMinutes ?? trace.medianMinutes {
                                    Text("\(minutes)分")
                                        .monospacedDigit()
                                }
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("予測の内部")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
        .toolbar {
            if !log.traces.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("消去") {
                        log.clear()
                    }
                }
            }
        }
    }
}

struct DeveloperForecastTraceView: View {
    let trace: ArrivalForecastTrace

    var body: some View {
        List {
            Section("結果") {
                LabeledContent("結果", value: trace.outcome.displayLabel)
                LabeledContent("モデル", value: trace.modelAvailability)
                LabeledContent("所要", value: "\(trace.elapsedMilliseconds) ms")
                if let parsed = trace.parsedMinutes {
                    LabeledContent("読み取り", value: "\(parsed)分")
                }
                if let clamped = trace.clampedMinutes {
                    LabeledContent("採用", value: "\(clamped)分")
                }
                if let weight = trace.weightLabel {
                    LabeledContent("重さ", value: weight)
                }
                if let confidence = trace.confidenceLabel {
                    LabeledContent("確度", value: confidence)
                }
                if let error = trace.errorDescription, !error.isEmpty {
                    LabeledContent("エラー") {
                        Text(error)
                            .textSelection(.enabled)
                    }
                }
            }

            if let thinking = trace.thinking, !thinking.isEmpty {
                Section("推論") {
                    Text(thinking)
                        .textSelection(.enabled)
                }
            }

            if let reasoning = trace.nativeReasoning, !reasoning.isEmpty {
                Section("モデルの思考") {
                    Text(reasoning)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section("入力") {
                LabeledContent("題名", value: trace.title)
                if !trace.tagNames.isEmpty {
                    LabeledContent("経由", value: trace.tagNames.joined(separator: "、"))
                }
                if let estimated = trace.estimatedMinutes {
                    LabeledContent("見積もり", value: "\(estimated)分")
                }
                if let hour = trace.hour, let band = trace.bandName {
                    LabeledContent("時間帯", value: "\(hour)時（\(band)）")
                }
                if let median = trace.medianMinutes, let count = trace.sampleCount {
                    LabeledContent("中央値", value: "\(median)分 / \(count)件")
                }
                if let bandCount = trace.bandSampleCount {
                    LabeledContent("同じ時間帯", value: "\(bandCount)件")
                }
                if let recent = trace.recentLine {
                    LabeledContent("最近") {
                        Text(recent)
                            .textSelection(.enabled)
                    }
                }
            }

            if let prompt = trace.prompt {
                Section("プロンプト") {
                    if let instructions = trace.instructions {
                        Text(instructions)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                    }
                    Text(prompt)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let raw = trace.rawResponse {
                Section("生応答") {
                    Text(raw)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("1 回分")
        .navigationBarTitleDisplayMode(.inline)
    }
}
