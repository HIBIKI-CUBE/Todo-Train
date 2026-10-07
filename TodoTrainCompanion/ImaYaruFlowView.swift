import SwiftUI
import TodoTrainSync
import TodoTrainTicketUI

/// Mac panel: title, duration, and a button. The Mars face is not in this window.
struct ImaYaruFormView: View {
    @Environment(CompanionMacRuntime.self) private var runtime

    var initialNotice: String?
    var seededTitle: String = ""
    var seededMinutes: Int = 30
    var seededPrior: UUID?
    var onDispense: (_ title: String, _ minutes: Int, _ priorSessionId: UUID?) -> Void
    var onClose: () -> Void

    @State private var title = ""
    @State private var minutes = 30
    @State private var phase: FormPhase = .editing
    @State private var notice: String?
    @State private var noticeIsFailure = false
    @State private var sendID = 0
    @State private var sentTitle = ""
    @State private var sentMinutes = 30
    @State private var sentPrior: UUID?
    @FocusState private var titleFocused: Bool

    private enum FormPhase {
        case editing
        case sending
    }

    private var trimmedTitle: String {
        IssueAndBoardEvaluating.trimmedTitle(title)
    }

    private var canIssue: Bool {
        IssueAndBoardEvaluating.isValid(title: trimmedTitle, estimatedSeconds: minutes * 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("何をする？", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)
                .onSubmit(commit)
                .disabled(phase != .editing)

            VStack(alignment: .leading, spacing: 8) {
                Text("所要（分）")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("所要", selection: $minutes) {
                    ForEach(EstimateSnapMapping.stops, id: \.self) { stop in
                        Text("\(stop)").tag(stop)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(phase != .editing)
            }

            if let notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(noticeIsFailure ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("キャンセル", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button(phase == .sending ? "送っています…" : "発車") {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(phase != .editing || !canIssue)
            }
        }
        .padding(20)
        .frame(width: 400, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if title.isEmpty {
                minutes = EstimateSnapMapping.snap(rawMinutes: Double(seededMinutes))
                if !seededTitle.isEmpty {
                    title = seededTitle
                    sentTitle = seededTitle
                    sentMinutes = minutes
                    sentPrior = seededPrior
                }
            }
            if notice == nil {
                notice = initialNotice
                noticeIsFailure = initialNotice != nil
            }
            titleFocused = true
            noteProgress()
        }
        .onChange(of: runtime.issueBoardTrack) { _, _ in
            noteProgress()
        }
        .onChange(of: runtime.snap) { _, _ in
            noteProgress()
        }
        .onExitCommand(perform: onClose)
        .task(id: sendID) {
            guard phase == .sending else { return }
            try? await Task.sleep(for: .seconds(ImaYaruWait.captionAfter))
            guard phase == .sending else { return }
            notice = SyncCopy.waitingForIPhone
            noticeIsFailure = false
            let rest = ImaYaruWait.limit - ImaYaruWait.captionAfter
            try? await Task.sleep(for: .seconds(rest))
            guard phase == .sending else { return }
            runtime.suppressRideOverlay = false
            phase = .editing
            notice = SyncCopy.iphoneNoReply
            noticeIsFailure = true
        }
    }

    private var rideConfirmed: Bool {
        guard phase == .sending else { return false }
        return ImaYaruSnap.confirms(
            snap: runtime.snap,
            title: sentTitle,
            priorSessionId: sentPrior
        )
    }

    private func commit() {
        guard phase == .editing, canIssue else { return }
        let trimmed = trimmedTitle
        sentTitle = trimmed
        sentMinutes = minutes
        sentPrior = ImaYaruOffer.ridingSessionID(runtime.snap)
        notice = SyncCopy.sentToIPhone
        noticeIsFailure = false
        phase = .sending
        runtime.suppressRideOverlay = true
        sendID += 1
        let seconds = minutes * 60
        Task { await runtime.sendIssueAndBoard(title: trimmed, estimatedSeconds: seconds) }
    }

    private func noteProgress() {
        guard phase == .sending else {
            if notice == SyncCopy.iphoneNoReply, snapMatchesSent {
                notice = nil
                onClose()
            }
            return
        }
        switch ImaYaruCommit.next(track: runtime.issueBoardTrack, rideConfirmed: rideConfirmed) {
        case .wait:
            break
        case .dispense:
            phase = .editing
            sendID += 1
            onDispense(sentTitle, sentMinutes, sentPrior)
        case .fail(let error):
            runtime.suppressRideOverlay = false
            phase = .editing
            notice = MenuBarPresentation.failureCopy(error)
            noticeIsFailure = true
        }
    }

    private var snapMatchesSent: Bool {
        ImaYaruSnap.confirms(snap: runtime.snap, title: sentTitle, priorSessionId: sentPrior)
    }
}

@MainActor
@Observable
final class ImaYaruDispenseModel {
    var seated = false
    var handingOff = false
    var showsWait = false
    var gaveUp = false
}

/// Mars ticket only. The window itself slides in from off-screen.
struct ImaYaruDispenseView: View {
    @Environment(CompanionMacRuntime.self) private var runtime
    @Bindable var model: ImaYaruDispenseModel
    @State private var armedReveal = false

    var title: String
    var minutes: Int
    var ticketSize: CGSize
    var priorSessionId: UUID?
    var onReveal: () -> Void
    var onGiveUp: () -> Void
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            MarsTicketView(
                content: MarsTicketContent(title: title, minutes: minutes)
            )
            .frame(width: ticketSize.width, height: ticketSize.height)
            .scaleEffect(model.handingOff ? 0.94 : 1)
            .opacity(model.handingOff ? 0 : 1)

            if model.gaveUp {
                caption(SyncCopy.iphoneNoReply, failure: true)
            } else if model.showsWait && !model.handingOff {
                caption(SyncCopy.waitingForIPhone, failure: false)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.handingOff)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("発券。\(title)。\(minutes)分")
        .onAppear {
            tryReveal()
        }
        .onChange(of: model.seated) { _, _ in
            tryReveal()
        }
        .onChange(of: runtime.snap) { _, _ in
            tryReveal()
        }
        .onExitCommand(perform: onClose)
        .task(id: armedReveal) {
            guard armedReveal else { return }
            try? await Task.sleep(for: .seconds(ImaYaruWait.ticketHold))
            guard !Task.isCancelled, model.seated, !model.handingOff else { return }
            guard ImaYaruSnap.confirms(snap: runtime.snap, title: title, priorSessionId: priorSessionId) else {
                armedReveal = false
                return
            }
            model.showsWait = false
            model.gaveUp = false
            model.handingOff = true
            onReveal()
        }
        .task {
            try? await Task.sleep(for: .seconds(ImaYaruWait.captionAfter))
            guard !model.handingOff, !model.gaveUp else { return }
            model.showsWait = true
            let rest = ImaYaruWait.limit - ImaYaruWait.captionAfter
            try? await Task.sleep(for: .seconds(rest))
            guard !model.handingOff, !model.gaveUp else { return }
            model.showsWait = false
            model.gaveUp = true
            try? await Task.sleep(for: .seconds(1.4))
            guard !model.handingOff else { return }
            onGiveUp()
        }
    }

    private func caption(_ text: String, failure: Bool) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(failure ? Color.red : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 8)
    }

    private func tryReveal() {
        guard model.seated, !model.handingOff, !armedReveal else { return }
        guard ImaYaruSnap.confirms(snap: runtime.snap, title: title, priorSessionId: priorSessionId) else {
            return
        }
        armedReveal = true
    }
}
