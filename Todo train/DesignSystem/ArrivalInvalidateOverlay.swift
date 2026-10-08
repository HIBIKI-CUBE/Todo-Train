//
//  ArrivalInvalidateOverlay.swift
//  Todo train
//
//  到着の締め。行き先を選んで検札印を押す。検札では発車しない。
//  別の切符と即時切符は到着画面の上に重ね、閉じると到着画面に戻る。
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ArrivalInvalidateOverlay: View {
    let moment: PunctualityMoment
    /// Cover is still up — start already settled so dismiss *is* the reveal (no second entrance).
    var skipEnter: Bool = false
    var onClose: () -> Void
    var onStamp: (UUID, ArrivalAction) throws -> Void
    var onIssueInstant: (String, Int) throws -> ArrivalTicketFace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(SessionManager.self) private var sessionManager
    @Environment(AppSettings.self) private var settings

    @State private var deck = ArrivalDeck(reserved: nil)
    @State private var didSeedDeck = false
    @State private var instantTitle = ""
    @State private var instantMinutes = EstimateHeuristic.defaultHighlightMinutes
    @State private var didSeedMinutes = false
    @State private var issueError = ""

    /// 0 hidden below → 1 settled and waiting.
    @State private var enter: CGFloat = 0
    /// User press 0…1 (extends the same downward path as the invite).
    @State private var press: CGFloat = 0
    /// 0…1 ink on ticket; handle crossfades out.
    @State private var impact: CGFloat = 0
    @State private var inviting = false
    @State private var stampHaptic = 0

    private var arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)? {
        switch moment.kind {
        case .arrival(let title, let estimate, _, let punctuality):
            (title, max(estimate / 60, 1), punctuality)
        case .onTimeService:
            nil
        }
    }

    private var otherFaces: [ArrivalTicketFace] {
        let reservedID = deck.reserved?.id
        return sessionManager.openTicketsInHubOrder()
            .filter { $0.id != reservedID }
            .map {
                ArrivalTicketFace(
                    id: $0.id,
                    title: $0.title,
                    minutes: max($0.estimatedSeconds / 60, 1)
                )
            }
    }

    private var curve: Animation {
        MarsTicketSpec.ArrivalMotion.arc
    }

    var body: some View {
        Group {
            if let arrival {
                scene(arrival: arrival)
            }
        }
        .onAppear {
            seedDeckIfNeeded()
            seedMinutesIfNeeded()
        }
    }

    @ViewBuilder
    private func scene(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> some View {
        let ticket = MarsTicketContent(title: arrival.title, minutes: arrival.minutes)
        let scrim = 0.12 + 0.23 * Double(enter)

        ZStack {
            Color.black.opacity(scrim).ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    MarsTicketView(content: ticket, titleReveal: 1)
                        .padding(.horizontal, MarsTicketSpec.horizontalMargin)
                        .overlay {
                            MarsTicketUsedMarks(
                                punctuality: arrival.punctuality,
                                stampSettled: impact
                            )
                            .padding(.horizontal, MarsTicketSpec.horizontalMargin)
                            .opacity(Double(impact))
                        }
                        .scaleEffect(1 - 0.012 * impact)

                    if !reduceMotion, deck.stampedFace == nil {
                        stampHandle(punctuality: arrival.punctuality)
                            .offset(y: stampY)
                            .opacity(stampOpacity)
                            .scaleEffect(1 - 0.08 * press)
                            .gesture(pressGesture(punctuality: arrival.punctuality))
                            .allowsHitTesting(deck.canStamp)
                    }
                }
                .frame(maxHeight: 280)

                destinationBar(punctuality: arrival.punctuality)
                    .padding(.horizontal, 20)
            }
            .offset(y: sceneY)
            .opacity(Double(max(0, enter)))

            if deck.picker == .otherTickets {
                otherTicketPicker
            }
            if deck.picker == .instant {
                instantTicketPicker
            }
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: stampHaptic)
        .onAppear {
            announceIfNeeded(arrival: arrival)
            runEntrance()
        }
    }

    private var sceneY: CGFloat {
        let rise = (1 - enter) * 36
        let dip = press * 6 + impact * 10
        return rise + dip
    }

    private var stampY: CGFloat {
        let rest: CGFloat = -44
        let fromAbove = (1 - enter) * -28
        let invite = inviting && press < 0.02 && impact < 0.01
            ? MarsTicketSpec.ArrivalMotion.nudgeAmplitude
            : 0
        let towardInk = press * 40 + impact * 8
        return rest + fromAbove + invite + towardInk
    }

    private var stampOpacity: Double {
        deck.canStamp ? Double(enter) : 0.35 * Double(enter)
    }

    @ViewBuilder
    private func destinationBar(punctuality: ArrivalPunctuality) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nextRideRow
            if deck.stampedFace == nil {
                HStack(spacing: 8) {
                    Button("別の切符") { deck.showOtherTickets() }
                        .buttonStyle(.bordered)
                    Button("即時切符") { deck.showInstant() }
                        .buttonStyle(.bordered)
                }
                if reduceMotion {
                    Button("検札する") {
                        commitStamp(punctuality: punctuality)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MarsTicketSpec.stampBlue)
                    .disabled(!deck.canStamp)
                }
            } else if let face = deck.stampedFace {
                Text(face.title)
                    .font(.headline)
                Text("検札しました")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("閉じる", action: onClose)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAction(.default) {
            commitStamp(punctuality: punctuality)
        }
    }

    private var nextRideRow: some View {
        HStack {
            Text("次の一本")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if let reserved = deck.reserved {
                Button(reserved.title) {
                    deck.selectNextRide()
                }
                .disabled(deck.stampedFace != nil)
            } else {
                Text("予約なし")
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var otherTicketPicker: some View {
        NavigationStack {
            List(otherFaces) { face in
                Button(face.title) {
                    deck.selectOther(face)
                }
            }
            .navigationTitle("別の切符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { deck.dismissPicker() }
                }
            }
            .overlay {
                if otherFaces.isEmpty {
                    Text("開いている切符がありません")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var instantTicketPicker: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("何をする？", text: $instantTitle)
                    .textFieldStyle(.roundedBorder)
                EstimateChips(
                    minutesOptions: EstimateChips.ticketPresets,
                    style: .plainMinutes,
                    selectedMinutes: instantMinutes,
                    onSelect: { instantMinutes = $0 }
                )
                if !issueError.isEmpty {
                    Text(issueError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Button("発行") { issueInstant() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(20)
            .navigationTitle("即時切符")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") {
                        issueError = ""
                        deck.dismissPicker()
                    }
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func pressGesture(punctuality: ArrivalPunctuality) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard deck.canStamp, !reduceMotion else { return }
                inviting = false
                let dy = max(0, value.translation.height)
                press = min(1, dy / 88)
                if press > 0.82 {
                    commitStamp(punctuality: punctuality)
                }
            }
            .onEnded { value in
                guard deck.canStamp, impact < 1 else { return }
                let travel = hypot(value.translation.width, value.translation.height)
                if travel < 14 || value.translation.height > 64 || press > 0.55 {
                    commitStamp(punctuality: punctuality)
                } else {
                    withAnimation(curve) { press = 0 }
                    resumeInvite()
                }
            }
    }

    private func seedDeckIfNeeded() {
        guard !didSeedDeck else { return }
        didSeedDeck = true
        let reserved = sessionManager.reservedNextTicket().map { ticket in
            ArrivalTicketFace(
                id: ticket.id,
                title: ticket.title,
                minutes: max(ticket.estimatedSeconds / 60, 1)
            )
        }
        deck = ArrivalDeck(reserved: reserved)
    }

    private func seedMinutesIfNeeded() {
        guard !didSeedMinutes else { return }
        didSeedMinutes = true
        instantMinutes = settings.lastIssuedEstimateMinutes ?? EstimateHeuristic.defaultHighlightMinutes
    }

    private func issueInstant() {
        do {
            let face = try onIssueInstant(instantTitle, instantMinutes)
            issueError = ""
            deck.selectInstant(face)
        } catch {
            issueError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func runEntrance() {
        press = 0
        impact = 0

        if reduceMotion || skipEnter {
            enter = 1
            resumeInvite()
            return
        }

        enter = 0
        withAnimation(MarsTicketSpec.ArrivalMotion.enter) {
            enter = 1
        } completion: {
            resumeInvite()
        }
    }

    private func resumeInvite() {
        guard deck.canStamp, !reduceMotion, impact < 0.01 else { return }
        inviting = false
        withAnimation(
            MarsTicketSpec.ArrivalMotion.invite
                .repeatForever(autoreverses: true)
        ) {
            inviting = true
        }
    }

    private func stampHandle(punctuality: ArrivalPunctuality) -> some View {
        let ink = stampInk(punctuality)
        return VStack(spacing: 4) {
            Capsule()
                .fill(ink.opacity(0.85))
                .frame(width: 16, height: 28)
            Circle()
                .strokeBorder(ink, lineWidth: 2.4)
                .background(Circle().fill(ink.opacity(0.1)))
                .frame(width: 52, height: 52)
                .overlay {
                    Text(stampCenterLabel(punctuality))
                        .font(.system(size: 11, weight: .bold, design: .default))
                        .foregroundStyle(ink)
                }
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .contentShape(Rectangle())
        .accessibilityLabel("検札印")
        .accessibilityHint(deck.canStamp ? "ダブルタップで検札印を押す" : "行き先が決まるまで押せません")
    }

    private func stampInk(_ punctuality: ArrivalPunctuality) -> Color {
        switch punctuality {
        case .early: MarsTicketSpec.stampPurple
        case .onTime: MarsTicketSpec.stampBlue
        case .late, .notApplicable: MarsTicketSpec.stampBlue.opacity(0.9)
        }
    }

    private func stampCenterLabel(_ punctuality: ArrivalPunctuality) -> String {
        switch punctuality {
        case .onTime: "定時"
        case .early: "早着"
        case .late, .notApplicable: "到着"
        }
    }

    private func commitStamp(punctuality: ArrivalPunctuality) {
        guard let selection = deck.stampSelection(),
              let sessionID = moment.arrivedSessionID
        else { return }
        do {
            try onStamp(sessionID, selection.action)
        } catch {
            return
        }
        deck.markStamped()
        inviting = false
        stampHaptic += 1

        withAnimation(MarsTicketSpec.ArrivalMotion.slam) {
            press = 1
            impact = 1
        } completion: {
            if punctuality == .onTime || punctuality == .early {
                stampHaptic += 1
            }
        }
    }

    private func accessibilityText(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> String {
        let head = Punctuality.arrivalHeadline(arrival.punctuality)
        if deck.canStamp {
            return "\(head)。\(arrival.title)。検札印を押してください"
        }
        return "\(head)。\(arrival.title)。行き先を選ぶか、閉じてください"
    }

    private func announceIfNeeded(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) {
        #if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: accessibilityText(arrival: arrival))
        #endif
    }
}

/// Punch hole + small circular stamp (≤ ~1/5 of ticket).
struct MarsTicketUsedMarks: View {
    var punctuality: ArrivalPunctuality = .late
    var stampSettled: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            let stampSize = min(geo.size.width, geo.size.height) * 0.28
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color.black.opacity(0.55 * stampSettled))
                    .frame(width: 11, height: 11)
                    .overlay {
                        Circle().strokeBorder(MarsTicketSpec.printInk.opacity(0.35), lineWidth: 0.5)
                    }
                    .offset(x: 10, y: geo.size.height * 0.42)

                stampDisk(size: stampSize)
                    .scaleEffect(0.72 + 0.28 * stampSettled)
                    .opacity(Double(stampSettled))
                    .offset(
                        x: geo.size.width * 0.55,
                        y: geo.size.height * 0.48
                    )
                    .rotationEffect(.degrees(-12))
            }
        }
        .allowsHitTesting(false)
    }

    private func stampDisk(size: CGFloat) -> some View {
        let ink: Color = {
            switch punctuality {
            case .early: MarsTicketSpec.stampPurple
            case .onTime: MarsTicketSpec.stampBlue
            case .late, .notApplicable: MarsTicketSpec.stampBlue.opacity(0.9)
            }
        }()
        return ZStack {
            Circle()
                .strokeBorder(ink.opacity(0.85), lineWidth: 2.2)
            Circle()
                .strokeBorder(ink.opacity(0.35), lineWidth: 0.8)
                .padding(4)
            VStack(spacing: 2) {
                Text("ありがとうございます")
                    .font(.system(size: 6, weight: .semibold, design: .default))
                    .foregroundStyle(ink.opacity(0.8))
                Text(stampCenterLabel)
                    .font(MarsTicketSpec.stampFont())
                    .foregroundStyle(ink)
            }
        }
        .frame(width: size, height: size)
    }

    private var stampCenterLabel: String {
        switch punctuality {
        case .onTime: "定時"
        case .early: "早着"
        case .late, .notApplicable: "到着"
        }
    }
}

#Preview("Arrival stamp") {
    let container = try! AppModelContainer.make(inMemory: true)
    let manager = SessionManager(modelContext: container.mainContext)
    return ArrivalInvalidateOverlay(
        moment: PunctualityMoment(
            kind: .arrival(
                title: "週次レビューの下書き",
                estimateSeconds: 1_500,
                actualSeconds: 1_440,
                punctuality: .onTime
            )
        ),
        onClose: {},
        onStamp: { _, _ in },
        onIssueInstant: { title, minutes in
            ArrivalTicketFace(id: UUID(), title: title, minutes: minutes)
        }
    )
    .environment(manager)
    .environment(AppSettings.shared)
    .modelContainer(container)
}
