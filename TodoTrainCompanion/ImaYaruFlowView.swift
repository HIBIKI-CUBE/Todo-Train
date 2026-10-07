import SwiftUI
import TodoTrainSync
import TodoTrainTicketUI

/// One fixed canvas: title + gauge, then the shared eject, then the existing ride PiP.
struct ImaYaruFlowView: View {
    @Environment(CompanionMacRuntime.self) private var runtime

    var onHandOff: () -> Void
    var onClose: () -> Void

    @State private var title = ""
    @State private var minutes = 30
    @State private var focusNonce = 0
    @State private var phase: ImaYaruPhase = .composing
    @State private var event: TicketIssueEjectEvent?
    @State private var customMinutes = false

    private var trimmedTitle: String {
        IssueAndBoardEvaluating.trimmedTitle(title)
    }

    private var canIssue: Bool {
        IssueAndBoardEvaluating.isValid(title: trimmedTitle, estimatedSeconds: minutes * 60)
    }

    var body: some View {
        ZStack {
            VStack(spacing: ImaYaruCanvas.stackSpacing) {
                titleRail
                gaugeRail
                ticketSlot
            }
            .padding(.horizontal, ImaYaruCanvas.horizontalPad)
            .padding(.vertical, ImaYaruCanvas.verticalPad)
            .opacity(showsComposer ? 1 : 0)
            .allowsHitTesting(phase == .composing)

            if showsEject, let event {
                TicketIssueEjectOverlay(
                    event: event,
                    finish: .zoomIntoFocus,
                    onFinished: finishEject
                )
            }

            if phase == .failed {
                failureBanner
            }
        }
        .frame(width: ImaYaruCanvas.size.width, height: ImaYaruCanvas.size.height)
        .background(.regularMaterial)
        .onAppear { focusNonce += 1 }
        .onChange(of: runtime.issueBoardTrack) { _, _ in
            noteTrack()
        }
        .onChange(of: runtime.snap) { _, _ in
            tryHandOff()
        }
        .onExitCommand { onClose() }
    }

    private var showsComposer: Bool {
        phase == .composing || phase == .failed
    }

    private var showsEject: Bool {
        phase == .ejecting || phase == .holding
    }

    private var titleRail: some View {
        ComposingTextField(
            text: $title,
            placeholder: "何をする？",
            focusNonce: focusNonce,
            onSubmit: commit
        )
        .frame(height: ImaYaruCanvas.titleRail, alignment: .center)
    }

    private var gaugeRail: some View {
        ZStack {
            if customMinutes {
                CustomEstimateInput(minutes: $minutes)
            } else {
                EstimateSnapGauge(
                    minutes: $minutes,
                    highlightedMinutes: 30,
                    willIssue: { canIssue },
                    onCommit: commit,
                    onLongPress: { customMinutes = true }
                )
                .frame(height: 48)
            }
        }
        .frame(height: ImaYaruCanvas.gaugeRail)
    }

    private var ticketSlot: some View {
        MarsTicketView(
            content: MarsTicketContent(
                title: trimmedTitle.isEmpty ? " " : trimmedTitle,
                minutes: minutes
            )
        )
        .frame(height: ImaYaruCanvas.ticketSlotHeight)
        .opacity(trimmedTitle.isEmpty ? 0.35 : 1)
        .accessibilityHidden(trimmedTitle.isEmpty)
    }

    private var failureBanner: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Text(failureLine)
                    .font(.callout)
                    .foregroundStyle(.red)
                Spacer(minLength: 8)
                Button("閉じる", action: onClose)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding(16)
        }
    }

    private var failureLine: String {
        if case .failed(let error) = runtime.issueBoardTrack {
            return MenuBarPresentation.failureCopy(error)
        }
        return SyncCopy.invalidPayload
    }

    private func commit() {
        guard phase == .composing, canIssue else { return }
        let issued = TicketIssueEjectEvent(
            ticketID: UUID(),
            title: trimmedTitle,
            minutes: minutes
        )
        event = issued
        phase = .ejecting
        let seconds = minutes * 60
        let sentTitle = trimmedTitle
        Task { await runtime.sendIssueAndBoard(title: sentTitle, estimatedSeconds: seconds) }
    }

    private func finishEject() {
        if case .failed = runtime.issueBoardTrack {
            phase = .failed
            return
        }
        if phase == .ejecting {
            phase = .holding
        }
        tryHandOff()
    }

    private func noteTrack() {
        if case .failed = runtime.issueBoardTrack, phase != .composing {
            if phase != .ejecting {
                phase = .failed
            }
        }
        tryHandOff()
    }

    private func tryHandOff() {
        guard phase == .holding else { return }
        guard case .acked(_, let sentTitle, let prior) = runtime.issueBoardTrack else { return }
        guard ImaYaruSnap.confirms(snap: runtime.snap, title: sentTitle, priorSessionId: prior) else { return }
        onHandOff()
    }
}
