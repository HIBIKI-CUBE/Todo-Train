import AppKit
import SwiftUI
import TodoTrainSync

struct PairingWindow: View {
    @Environment(CompanionMacRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss

    @State private var flow: PairingFlow?
    @State private var qr: PairingURL?
    @State private var phase: PairingPhase = .idle
    @State private var errorText: String?
    @State private var bindTask: Task<Void, Never>?
    @State private var confirmTask: Task<Void, Never>?

    var body: some View {
        HSplitView {
            VStack(spacing: 16) {
                Text("大きな QR")
                    .font(.headline)
                if let encoded = qr?.encoded {
                    CompanionQRCodeView(encoded: encoded)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.06))
                        .frame(width: 312, height: 312)
                }
                Spacer()
            }
            .frame(minWidth: 340)
            .padding(20)

            VStack(alignment: .leading, spacing: 16) {
                Text(instruction)
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                ZStack {
                    CompanionCameraPreview { handleOptical($0) }
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(24)
                }
                .frame(minHeight: 240)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if phase == .awaitingLocalAuth || phase == .confirming {
                    Button("自分に戻して Touch ID") {
                        confirmTask?.cancel()
                        confirmTask = Task { await confirm() }
                    }
                    .keyboardShortcut(.defaultAction)
                }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.callout)
                }

                Spacer()
            }
            .padding(20)
            .frame(minWidth: 360)
        }
        .frame(minWidth: 720, minHeight: 480)
        .task { await start() }
        .onDisappear {
            bindTask?.cancel()
            confirmTask?.cancel()
            Task { try? await flow?.abort() }
        }
    }

    private var instruction: String {
        switch phase {
        case .established:
            "つながった。この Mac だけが読める。"
        case .awaitingLocalAuth, .confirming:
            "端末を自分に戻して Touch ID"
        case .aborted:
            "やり直してください"
        default:
            "iPhone の画面をこの枠に入れる"
        }
    }

    private func start() async {
        do {
            let pairing = try runtime.makeFlow()
            flow = pairing
            qr = try await pairing.presentQR()
            phase = await pairing.phase
        } catch {
            errorText = "リレー URL を設定に書いてから、もう一度。"
        }
    }

    private func handleOptical(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        Task { await ingest(trimmed) }
    }

    private func ingest(_ urlString: String) async {
        guard let flow else { return }
        do {
            _ = try await flow.ingestOptical(urlString)
            phase = await flow.phase
            bindTask?.cancel()
            bindTask = Task { await pollBind() }
        } catch {
            errorText = "その QR ではつながらない"
        }
    }

    private func pollBind() async {
        guard let flow else { return }
        for _ in 0..<40 {
            if Task.isCancelled { return }
            do {
                let response = try await flow.refreshBind()
                phase = await flow.phase
                if response.bound {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    return
                }
            } catch {
                errorText = "つなぎ直しが必要"
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func confirm() async {
        guard let flow else { return }
        let deadline = Date().addingTimeInterval(15)
        do {
            while Date() <= deadline {
                if Task.isCancelled { return }
                try await flow.authenticateAndConfirm()
                phase = await flow.phase
                if phase == .established {
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                    runtime.pairingDidEstablish()
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    dismiss()
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            errorText = "確定の時間切れ。自分に戻してもう一度。"
        } catch {
            errorText = "確定できなかった。自分に戻してからもう一度。"
        }
    }
}
