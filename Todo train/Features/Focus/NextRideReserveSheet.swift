//
//  NextRideReserveSheet.swift
//  Todo train
//
//  乗車中に本人が開いたときだけ出す予約欄。割り込み発行とは別。発車しない。
//

import SwiftData
import SwiftUI

struct NextRideReserveSheet: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var errorMessage = ""
    @State private var showError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let reserved = sessionManager.reservedNextTicket() {
                        Text(reserved.title)
                        Button("解除", role: .destructive) {
                            run { try sessionManager.clearNextRideReservation() }
                        }
                    } else {
                        Text("予約なし")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("次の一本")
                }

                Section {
                    let choices = sessionManager.ticketsAvailableToReserve()
                    if choices.isEmpty {
                        Text("開いている切符がありません")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(choices, id: \.id) { ticket in
                            Button(ticket.title) {
                                run {
                                    try sessionManager.reserveNextRide(ticket: ticket, via: .riding)
                                    dismiss()
                                }
                            }
                        }
                    }
                } header: {
                    Text("開いている切符")
                }
            }
            .navigationTitle("予約")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert("エラー", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func run(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            showError = true
        }
    }
}
