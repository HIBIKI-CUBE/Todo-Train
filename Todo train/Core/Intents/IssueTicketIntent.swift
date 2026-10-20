//
//  IssueTicketIntent.swift
//  Todo train
//

import AppIntents

struct IssueEstimateMinuteOptions: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<Int> {
        let items = EstimateSnapMapping.stops.map { minutes in
            IntentItem(
                minutes,
                title: LocalizedStringResource(stringLiteral: "\(minutes)分")
            )
        }
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }
}

struct IssueTicketIntent: AppIntent {
    static var title: LocalizedStringResource = "切符を発行"
    static var description = IntentDescription("Hub に新しい切符を追加します。発車はしません。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "題名")
    var title: String

    @Parameter(
        title: "見積もり（分）",
        requestValueDialog: "見積もりは何分ですか",
        optionsProvider: IssueEstimateMinuteOptions()
    )
    var minutes: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("「\(\.$title)」を\(\.$minutes)分で発行")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .result(dialog: "題名を入れてください")
        }

        let resolvedMinutes: Int
        if let minutes {
            resolvedMinutes = minutes
        } else {
            resolvedMinutes = try await $minutes.requestValue("見積もりは何分ですか")
        }

        let issued: (ticket: Ticket, minutes: Int)
        switch try InventoryIssueTarget.resolve(
            sessionManager: AppRuntime.sessionManager,
            modelContainer: AppRuntime.modelContainer,
            makeContainer: { try AppModelContainer.make() }
        ) {
        case .manager(let manager):
            issued = try manager.issueInventoryTicket(title: trimmed, minutes: resolvedMinutes)
        case .context(let context):
            issued = try InventoryTicketIssue.issue(
                title: trimmed,
                minutes: resolvedMinutes,
                into: context,
                settings: AppSettings.shared
            )
        }
        return .result(dialog: "「\(issued.ticket.title)」を \(issued.minutes) 分で発行しました")
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
