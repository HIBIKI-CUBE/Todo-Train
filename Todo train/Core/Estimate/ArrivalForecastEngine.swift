//
//  ArrivalForecastEngine.swift
//  Todo train
//
//  On-device minute refine for Hub prediction. Heuristic median is the skeleton.
//  The model thinks, then returns structured fields. Hub uses minutes only.
//  PCC / conversation / advice are not used.
//

import Foundation

@MainActor
protocol ArrivalForecasting {
    /// Adjusted minutes, or nil to keep the heuristic median.
    func refine(_ context: ArrivalForecastContext) async -> Int?
    /// Load model weights before the next refine. No-op when unavailable.
    func prepareForInference()
}

extension ArrivalForecasting {
    func prepareForInference() {}
}

struct HeuristicArrivalForecastEngine: ArrivalForecasting {
    var log: ArrivalForecastTraceLog = .shared

    func refine(_ context: ArrivalForecastContext) async -> Int? {
        log.record(
            .fromContext(
                context,
                outcome: .heuristicOnly,
                modelAvailability: "heuristic"
            )
        )
        return nil
    }
}

#if canImport(FoundationModels)
import FoundationModels

@Generable
struct ArrivalForecastGeneration {
    @Guide(description: "題名・見積・延長・早着を踏まえた短い推論。助言・励ましは書かない。")
    var thinking: String

    @Guide(description: "今回の予測分数。1から60の整数。", .range(1...60))
    var predictedMinutes: Int

    @Guide(description: "中央値より重い・同程度・軽い")
    var weight: Weight

    @Guide(description: "題名と履歴からの確度")
    var confidence: Confidence

    @Generable
    enum Weight {
        case lighter
        case similar
        case heavier
    }

    @Generable
    enum Confidence {
        case low
        case medium
        case high
    }
}

@MainActor
final class OnDeviceArrivalForecastEngine: ArrivalForecasting {
    var log: ArrivalForecastTraceLog = .shared
    private var primedSession: LanguageModelSession?

    func prepareForInference() {
        let model = SystemLanguageModel.default
        guard model.availability == .available else { return }
        if primedSession == nil {
            primedSession = LanguageModelSession(
                model: model,
                instructions: ArrivalForecastPrompt.instructions
            )
        }
        primedSession?.prewarm()
    }

    func refine(_ context: ArrivalForecastContext) async -> Int? {
        let started = Date()
        let prompt = ArrivalForecastPrompt.userPrompt(for: context)
        let instructions = ArrivalForecastPrompt.instructions
        let model = SystemLanguageModel.default
        let elapsed: () -> Int = {
            Int(Date().timeIntervalSince(started) * 1000)
        }

        guard model.availability == .available else {
            log.record(
                .fromContext(
                    context,
                    outcome: .modelUnavailable,
                    modelAvailability: "unavailable",
                    instructions: instructions,
                    prompt: prompt,
                    elapsedMilliseconds: elapsed()
                )
            )
            return nil
        }

        do {
            let result = try await generate(model: model, prompt: prompt, instructions: instructions)
            prepareForInference()
            let draft = result.draft
            let resolved = ArrivalForecast.resolvedMinutes(
                from: draft,
                medianMinutes: context.medianMinutes
            )
            let clamped = ArrivalForecast.clampPredicted(
                draft.predictedMinutes,
                around: context.medianMinutes
            )
            let outcome: ArrivalForecastOutcome = resolved == nil ? .keptMedian : .refined
            log.record(
                .fromContext(
                    context,
                    outcome: outcome,
                    modelAvailability: result.availability,
                    instructions: instructions,
                    prompt: prompt,
                    rawResponse: draft.debugDump,
                    parsedMinutes: draft.predictedMinutes,
                    clampedMinutes: resolved ?? clamped,
                    thinking: draft.thinking,
                    weightLabel: draft.weight.displayLabel,
                    confidenceLabel: draft.confidence.displayLabel,
                    nativeReasoning: result.nativeReasoning,
                    elapsedMilliseconds: elapsed()
                )
            )
            return resolved
        } catch {
            prepareForInference()
            if ArrivalForecast.isCancellation(error) { return nil }
            log.record(
                .fromContext(
                    context,
                    outcome: .modelError,
                    modelAvailability: Self.availabilityLabel(model),
                    instructions: instructions,
                    prompt: prompt,
                    errorDescription: error.localizedDescription,
                    elapsedMilliseconds: elapsed()
                )
            )
            return nil
        }
    }

    private struct GenerationResult {
        var draft: ArrivalForecastDraft
        var availability: String
        var nativeReasoning: String?
    }

    /// Native reasoning is a separate capability from guided generation.
    /// The default on-device model can fill @Generable fields (including thinking)
    /// but throws `unsupportedCapability` if we ask for reasoningLevel.
    private func generate(
        model: SystemLanguageModel,
        prompt: String,
        instructions: String
    ) async throws -> GenerationResult {
        if model.capabilities.contains(.reasoning) {
            let session = takeSession(model: model, instructions: instructions)
            do {
                let generated = try await session.respond(
                    to: prompt,
                    generating: ArrivalForecastGeneration.self,
                    contextOptions: ContextOptions(
                        includeSchemaInPrompt: true,
                        reasoningLevel: .moderate
                    )
                ).content
                return GenerationResult(
                    draft: Self.draft(from: generated),
                    availability: Self.availabilityLabel(model) + " · reasoning",
                    nativeReasoning: Self.reasoningText(from: session)
                )
            } catch {
                if ArrivalForecast.isCancellation(error) { throw error }
                guard Self.isUnsupportedCapability(error) else { throw error }
            }
        }

        let session = takeSession(model: model, instructions: instructions)
        let generated = try await session.respond(
            to: prompt,
            generating: ArrivalForecastGeneration.self
        ).content
        return GenerationResult(
            draft: Self.draft(from: generated),
            availability: Self.availabilityLabel(model),
            nativeReasoning: Self.reasoningText(from: session)
        )
    }

    private func takeSession(
        model: SystemLanguageModel,
        instructions: String
    ) -> LanguageModelSession {
        if let primedSession {
            self.primedSession = nil
            return primedSession
        }
        return LanguageModelSession(model: model, instructions: instructions)
    }

    private static func availabilityLabel(_ model: SystemLanguageModel) -> String {
        var parts = ["available"]
        if model.capabilities.contains(.guidedGeneration) {
            parts.append("guided")
        }
        if model.capabilities.contains(.reasoning) {
            parts.append("can-reason")
        }
        return parts.joined(separator: " · ")
    }

    private static func isUnsupportedCapability(_ error: Error) -> Bool {
        if let modelError = error as? LanguageModelError,
           case .unsupportedCapability = modelError {
            return true
        }
        return error.localizedDescription.localizedCaseInsensitiveContains("requested capability")
    }

    private static func draft(from generated: ArrivalForecastGeneration) -> ArrivalForecastDraft {
        ArrivalForecastDraft(
            thinking: generated.thinking.trimmingCharacters(in: .whitespacesAndNewlines),
            predictedMinutes: generated.predictedMinutes,
            weight: weight(from: generated.weight),
            confidence: confidence(from: generated.confidence)
        )
    }

    private static func weight(from value: ArrivalForecastGeneration.Weight) -> ArrivalForecastWeight {
        switch value {
        case .lighter: .lighter
        case .similar: .similar
        case .heavier: .heavier
        }
    }

    private static func confidence(
        from value: ArrivalForecastGeneration.Confidence
    ) -> ArrivalForecastConfidence {
        switch value {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }

    private static func reasoningText(from session: LanguageModelSession) -> String? {
        let parts = session.transcript.compactMap { entry -> String? in
            guard case .reasoning(let reasoning) = entry else { return nil }
            let text = reasoning.description.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}
#endif

enum ArrivalForecastEngineFactory {
    @MainActor
    static func make() -> any ArrivalForecasting {
        #if canImport(FoundationModels)
        OnDeviceArrivalForecastEngine()
        #else
        HeuristicArrivalForecastEngine()
        #endif
    }
}
