import SwiftUI
import TodoTrainSync

struct CompanionPairingView: View {
    @Environment(CompanionSyncRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @State private var flow: PairingFlow?
    @State private var qr: PairingURL?
    @State private var phase: PairingPhase = .idle
    @State private var paste = ""
    @State private var errorText: String?
    @State private var bindTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: TrainTheme.Space.lg) {
                Text(instruction)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TrainTheme.Space.lg)

                if let encoded = qr?.encoded {
                    CompanionQRCodeView(encoded: encoded, dimension: 220)
                }

                if showsCamera {
                    ZStack {
                        if CompanionScannerSupport.isCameraUsable {
                            CompanionQRScanner { handleOptical($0) }
                        } else {
                            Color.black.opacity(0.12)
                        }
                        QRViewfinderFrame(color: TrainTheme.rail)
                            .padding(12)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: TrainTheme.Radius.control))
                    .padding(.horizontal, TrainTheme.Space.lg)
                }

                if phase == .awaitingLocalAuth || phase == .confirming {
                    Button("自分に戻して Face ID") {
                        Task { await confirm() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(TrainTheme.rail)
                }

                if showsPaste {
                    TextField("Mac の QR（todotrain://pair-mac…）", text: $paste)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal, TrainTheme.Space.lg)
                    Button("貼った URL を使う") {
                        handleOptical(paste)
                    }
                    .disabled(paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(TrainTheme.signalRed)
                        .padding(.horizontal, TrainTheme.Space.lg)
                }
            }
            .padding(.top, TrainTheme.Space.lg)
            .padding(.bottom, TrainTheme.Space.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(TrainTheme.platform)
        .navigationTitle("この Mac とつなぐ")
        .navigationBarTitleDisplayMode(
            TrainLayout.navigationBarTitleDisplayMode(verticalSizeClass: verticalSizeClass)
        )
        .task { await start() }
        .onDisappear {
            bindTask?.cancel()
            guard phase != .established else { return }
            let current = flow
            flow = nil
            Task { try? await current?.abort() }
        }
    }

    private var showsCamera: Bool {
        switch phase {
        case .presentingQR, .peerRead, .binding, .idle:
            true
        default:
            false
        }
    }

    private var showsPaste: Bool {
        showsCamera && CompanionScannerSupport.isCameraUsable == false
    }

    private var instruction: String {
        switch phase {
        case .established:
            "つながった。この Mac だけが読める。"
        case .awaitingLocalAuth, .confirming:
            "端末を自分に戻して Face ID"
        case .aborted:
            "やり直してください"
        default:
            "画面を Mac に向ける"
        }
    }

    private func start() async {
        do {
            let pairing = try runtime.makeFlow()
            flow = pairing
            qr = try await pairing.presentQR()
            phase = await pairing.phase
        } catch {
            errorText = SyncCopy.relayURLMissing
        }
    }

    private func handleOptical(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
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
            errorText = SyncCopy.invalidQR
        }
    }

    private func pollBind() async {
        guard let flow else { return }
        do {
            try await flow.waitUntilBound()
            phase = await flow.phase
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch is CancellationError {
            return
        } catch {
            errorText = SyncCopy.reconnectNeeded
        }
    }

    private func confirm() async {
        guard let flow else { return }
        do {
            try await flow.authenticateAndConfirm()
            phase = await flow.phase
            runtime.refreshPaired()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(nanoseconds: SyncTiming.pairingDismissPauseNanoseconds)
            dismiss()
        } catch {
            errorText = SyncCopy.confirmFailed
        }
    }
}
