//
//  IssueTicketIntent.swift
//  Todo train
//

import AppIntents
import SwiftData

struct IssueTicketIntent: AppIntent {
    static var title: LocalizedStringResource = "切符を発行"
    static var description = IntentDescription("Hub に新しい切符を追加します。発車はしません。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "題名")
    var title: String

    @Parameter(title: "見積もり（分）")
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("「\(\.$title)」の切符を発行")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "題名を入れてください")
        }

        // Prefer the running SessionManager so Hub's mainContext sees the insert.
        // Never open a sibling `ModelContext(container)` beside that mainContext.
        if let manager = AppRuntime.sessionManager {
            let issued = try manager.issueInventoryTicket(title: trimmed, minutes: minutes)
            return .result(dialog: "「\(issued.ticket.title)」を \(issued.minutes) 分で発行しました")
        }

        // Cold start (app not launched): one container, its mainContext only.
        let container = try AppModelContainer.make()
        let context = container.mainContext
        let sessions = (try? context.fetch(FetchDescriptor<WorkSession>())) ?? []
        let resolved = TicketIssuer.resolveMinutes(
            requested: minutes,
            sessions: sessions,
            lastIssued: AppSettings.shared.lastIssuedEstimateMinutes
        )
        let ticket = try TicketIssuer.issue(title: trimmed, minutes: resolved, into: context)
        AppSettings.shared.lastIssuedEstimateMinutes = resolved
        ArrivalForecastStore.shared.prefetch(ticket: ticket, sessions: sessions, priority: .user)
        return .result(dialog: "「\(ticket.title)」を \(resolved) 分で発行しました")
    }
}

struct TodoTrainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: IssueTicketIntent(),
            phrases: [
                "\(.applicationName)で切符を発行",
                "\(.applicationName)に切符を追加"
            ],
            shortTitle: "切符を発行",
            systemImageName: "plus"
        )
    }
}
