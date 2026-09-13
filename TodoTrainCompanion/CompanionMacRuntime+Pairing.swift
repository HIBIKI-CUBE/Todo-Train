import Foundation
import TodoTrainSync

extension CompanionMacRuntime {
    func makeFlow() throws -> PairingFlow {
        let url = try requireRelay()
        let client = SyncHTTPClient(
            baseURL: url,
            transport: URLSessionHTTPTransport(baseURL: url)
        )
        return PairingFlow(
            role: .mac,
            client: client,
            secrets: secrets,
            localAuth: localAuth
        )
    }

    func pairingDidEstablish() {
        refreshPaired()
        lastStatus = nil
        startListening()
    }

    func reconnect() {
        guard isPaired else { return }
        startListening()
    }

    func unpair() {
        pairingBindTask?.cancel()
        pairingConfirmTask?.cancel()
        pairingBindTask = nil
        pairingConfirmTask = nil
        pairingFlow = nil
        pairingPhase = .idle
        pairingQR = nil
        pairingCue = .scanning
        listenTask?.cancel()
        listenTask = nil
        hintTask?.cancel()
        hintTask = nil
        try? secrets.delete()
        snap = nil
        outgoingPause = .idle
        lastStatus = nil
        connection = .disconnected
        clearOptimisticCabin()
        optimisticIdleConsumed = false
        cabinNotifier.remove()
        refreshPaired()
    }

    var pairingCameraActive: Bool {
        guard pairingUIVisible, !isPaired else { return false }
        switch pairingPhase {
        case .presentingQR, .peerRead, .binding, .idle:
            switch pairingCue {
            case .authenticating, .established:
                return false
            default:
                return true
            }
        default:
            return false
        }
    }

    func pairingUIDidAppear() {
        pairingUIVisible = true
        if isPaired { return }
        switch pairingPhase {
        case .idle, .aborted:
            startPairing()
        default:
            if pairingCue.isFailed { startPairing() }
        }
    }

    func pairingUIDidDisappear() {
        pairingUIVisible = false
        switch pairingPhase {
        case .idle, .presentingQR, .aborted:
            abandonPairing(keepFailure: false)
        default:
            break
        }
    }

    func ingestOptical(_ urlString: String) {
        switch pairingPhase {
        case .presentingQR, .idle:
            break
        default:
            return
        }
        Task { await ingest(urlString) }
    }

    func startPairing() {
        abandonPairing(keepFailure: false)
        let epoch = pairingEpoch
        pairingScanGeneration += 1
        pairingCue = .scanning
        Task { await presentPairingQR(epoch: epoch) }
    }

    func abandonPairing(keepFailure: Bool) {
        pairingEpoch += 1
        pairingBindTask?.cancel()
        pairingConfirmTask?.cancel()
        let flow = pairingFlow
        pairingFlow = nil
        pairingQR = nil
        pairingPhase = keepFailure ? pairingPhase : .idle
        if !keepFailure { pairingCue = .scanning }
        Task { try? await flow?.abort() }
    }

    func presentPairingQR(epoch: Int) async {
        do {
            let pairing = try makeFlow()
            guard pairingEpoch == epoch else {
                try? await pairing.abort()
                return
            }
            pairingFlow = pairing
            pairingQR = try await pairing.presentQR(displayName: MacComputerName.current())
            guard pairingEpoch == epoch else {
                try? await pairing.abort()
                return
            }
            pairingPhase = await pairing.phase
            pairingCue = .scanning
        } catch {
            guard pairingEpoch == epoch else { return }
            pairingCue = .failed(SyncCopy.relayURLMissing)
        }
    }

    func ingest(_ urlString: String) async {
        guard let flow = pairingFlow else { return }
        do {
            let response = try await flow.ingestOptical(urlString)
            pairingPhase = await flow.phase
            pairingCue = .captured
            if response.bound {
                pairingCue = .authenticating
                beginConfirm(flow)
            } else {
                pairingCue = .waitingPeer
                pairingBindTask?.cancel()
                pairingBindTask = Task { await pollBind(flow) }
            }
        } catch {
            pairingScanGeneration += 1
            pairingCue = .failed(SyncCopy.invalidQR)
        }
    }

    func pollBind(_ flow: PairingFlow) async {
        do {
            try await flow.waitUntilBound()
            pairingPhase = await flow.phase
            pairingCue = .authenticating
            beginConfirm(flow)
        } catch is CancellationError {
            return
        } catch {
            pairingCue = .failed(SyncCopy.reconnectNeeded)
        }
    }

    func beginConfirm(_ flow: PairingFlow) {
        pairingConfirmTask?.cancel()
        pairingConfirmTask = Task { await confirm(flow) }
    }

    func confirm(_ flow: PairingFlow) async {
        pairingCue = .authenticating
        do {
            try await flow.authenticateAndConfirm()
            pairingPhase = await flow.phase
            if pairingPhase == .established {
                pairingCue = .established
                try? await Task.sleep(nanoseconds: SyncTiming.pairingEstablishedPauseNanoseconds)
                if Task.isCancelled { return }
                pairingDidEstablish()
                return
            }
            pairingCue = .failed(SyncCopy.confirmFailed)
        } catch is CancellationError {
            return
        } catch SyncError.confirmTimedOut {
            pairingCue = .failed(SyncCopy.confirmTimedOut)
        } catch SyncError.pairingAborted {
            pairingCue = .failed(SyncCopy.confirmFailed)
        } catch {
            pairingCue = .failed(pairingCopy(error))
        }
    }

    func pairingCopy(_ error: Error) -> String {
        SyncCopy.pairingFailure(error)
    }
}
