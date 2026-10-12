import Foundation
import SwiftData
import TodoTrainSync

extension SessionManager {
    /// Stored seconds only rise. The question is written once, and not after the pause ends.
    func applyPauseInputReport(_ command: CommandPlaintext) -> AckPlaintext {
        guard let report = PauseInputReport.make(
            sessionId: command.sessionId,
            pauseId: command.pauseId,
            macSampledSeconds: command.macSampledSeconds,
            macActiveSeconds: command.macActiveSeconds,
            promptedAt: command.promptedAt,
            promptAnswer: command.promptAnswer
        ) else {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
        do {
            let pauses = try modelContext.fetch(FetchDescriptor<SessionPause>())
            guard let pause = pauses.first(where: { $0.id == report.pauseId }) else {
                return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
            }
            guard pause.session?.id == report.sessionId else {
                return AckPlaintext(cmdId: command.id, ok: false, error: .sessionMismatch)
            }
            let merged = PauseInputRecord(
                macSampledSeconds: pause.macSampledSeconds,
                macActiveSeconds: pause.macActiveSeconds,
                promptedAt: pause.promptedAt.map { Int($0.timeIntervalSince1970) },
                promptAnswerRaw: pause.promptAnswerRaw,
                ended: pause.endedAt != nil
            ).merged(with: report)
            pause.macSampledSeconds = merged.macSampledSeconds
            pause.macActiveSeconds = merged.macActiveSeconds
            pause.promptedAt = merged.promptedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            pause.promptAnswerRaw = merged.promptAnswerRaw
            try save()
            return AckPlaintext(cmdId: command.id, ok: true)
        } catch {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
    }
}
