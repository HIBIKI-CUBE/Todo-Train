//
//  ServiceSummaryBar.swift
//  Todo train
//

import SwiftUI

struct ServiceSummaryBar: View {
    @Environment(SessionManager.self) private var sessionManager
    let onError: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sessionManager.needsServiceDayEndPrompt {
                Text("昨日の運行が未終了です。終了してから今日の運行を開始してください。")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sessionManager.isInService ? "運行中" : "運休")
                        .font(.headline)
                    if let key = sessionManager.activeServiceDay?.calendarDayKey, sessionManager.activeServiceDay?.isOpen == true {
                        Text(key)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text("停車 \(sessionManager.pausedTicketCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if sessionManager.isInService {
                    Button("運行終了", role: .destructive) {
                        do {
                            try sessionManager.endService()
                        } catch {
                            onError(error.localizedDescription)
                        }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("運行開始") {
                        do {
                            try sessionManager.startService()
                        } catch {
                            onError(error.localizedDescription)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
