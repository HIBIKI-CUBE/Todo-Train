import Foundation
import SwiftData
import TodoTrainSync

extension SessionManager {
    /// Last report for this pause wins. Ride time is left as it was recorded.
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
            pause.macSampledSeconds = report.macSampledSeconds
            pause.macActiveSeconds = report.macActiveSeconds
            if let promptedAt = report.promptedAt {
                pause.promptedAt = Date(timeIntervalSince1970: TimeInterval(promptedAt))
            }
            if let answer = report.promptAnswer {
                pause.promptAnswerRaw = answer.rawValue
            }
            try save()
            return AckPlaintext(cmdId: command.id, ok: true)
        } catch {
            return AckPlaintext(cmdId: command.id, ok: false, error: .invalidPayload)
        }
    }
}
