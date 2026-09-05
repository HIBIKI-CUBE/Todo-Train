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

    @Parameter(title: "タイトル")
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
            return .result(dialog: "切符の名前を入力してください")
        }

        let container = try resolvedContainer()
        let context = ModelContext(container)
        let sessions = (try? context.fetch(FetchDescriptor<WorkSession>())) ?? []
        let resolved = TicketIssuer.resolveMinutes(
            requested: minutes,
            sessions: sessions,
            lastIssued: AppSettings.shared.lastIssuedEstimateMinutes
        )
        let ticket = try TicketIssuer.issue(title: trimmed, minutes: resolved, into: context)
        AppSettings.shared.lastIssuedEstimateMinutes = resolved
        return .result(dialog: "「\(ticket.title)」を \(resolved) 分で発行しました")
    }

    @MainActor
    private func resolvedContainer() throws -> ModelContainer {
        if let container = AppRuntime.modelContainer {
            return container
        }
        return try AppModelContainer.make()
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
