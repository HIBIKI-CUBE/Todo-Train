//
//  IssueTicketIntent.swift
//  Todo train
//

import AppIntents

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

        let issued: (ticket: Ticket, minutes: Int)
        switch try InventoryIssueTarget.resolve(
            sessionManager: AppRuntime.sessionManager,
            modelContainer: AppRuntime.modelContainer,
            makeContainer: { try AppModelContainer.make() }
        ) {
        case .manager(let manager):
            issued = try manager.issueInventoryTicket(title: trimmed, minutes: minutes)
        case .context(let context):
            issued = try InventoryTicketIssue.issue(
                title: trimmed,
                minutes: minutes,
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
