//
//  ArrivalInvalidateOverlay.swift
//  Todo train
//
//  Arrival as one continuous arc: ticket+stamp enter together →
//  residual downward invite → user slam → ink blooms → same motion exits.
//  Not a tear. onTimeService stays on PunctualityMomentOverlay.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ArrivalInvalidateOverlay: View {
    let moment: PunctualityMoment
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 hidden below → 1 settled and waiting.
    @State private var enter: CGFloat = 0
    /// User press 0…1 (extends the same downward path as the invite).
    @State private var press: CGFloat = 0
    /// 0…1 ink on ticket; handle crossfades out.
    @State private var impact: CGFloat = 0
    /// 0…1 whole scene drifts away (continuation of the slam).
    @State private var exit: CGFloat = 0
    @State private var inviting = false
    @State private var locked = false
    @State private var stampHaptic = 0

    private var arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)? {
        switch moment.kind {
        case .arrival(let title, let estimate, _, let punctuality):
            (title, max(estimate / 60, 1), punctuality)
        case .onTimeService:
            nil
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
    }

    @ViewBuilder
    private func scene(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> some View {
        let ticket = MarsTicketContent(title: arrival.title, minutes: arrival.minutes)
        let scrim = 0.12 + 0.23 * Double(enter) * (1 - Double(exit) * 0.85)

        ZStack {
            Color.black.opacity(scrim).ignoresSafeArea()

            ZStack {
                // Ticket + ink — one body.
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
                    .scaleEffect(1 - 0.012 * impact - 0.02 * exit)

                // Handle lives in the same stack; never a separate “mode”.
                if !reduceMotion {
                    stampHandle(punctuality: arrival.punctuality)
                        .offset(y: stampY)
                        .opacity(Double((1 - impact) * enter * (1 - exit * 0.5)))
                        .scaleEffect(1 - 0.08 * press - 0.05 * impact)
                        .allowsHitTesting(false)
                }
            }
            .offset(y: sceneY)
            .opacity(Double(max(0, enter * (1 - exit))))

            if reduceMotion, locked == false, impact < 1 {
                Button("検札する") {
                    commitStamp(punctuality: arrival.punctuality)
                }
                .buttonStyle(.borderedProminent)
                .tint(MarsTicketSpec.stampBlue)
                .offset(y: 120)
            }
        }
        .contentShape(Rectangle())
        .gesture(pressGesture(punctuality: arrival.punctuality))
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1.0), trigger: stampHaptic)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(arrival: arrival))
        .accessibilityHint("ダブルタップで検札印を押す")
        .accessibilityAction(.default) {
            commitStamp(punctuality: arrival.punctuality)
        }
        .onAppear {
            announceIfNeeded(arrival: arrival)
            runEntrance()
        }
    }

    /// Whole composition shares one vertical arc (enter up → slam dip → exit down).
    private var sceneY: CGFloat {
        let rise = (1 - enter) * 36
        let dip = press * 6 + impact * 10
        let leave = exit * 56
        return rise + dip + leave
    }

    /// Stamp rides the same downward language from enter → invite → press → ink.
    private var stampY: CGFloat {
        let rest: CGFloat = -44
        let fromAbove = (1 - enter) * -28
        let invite = inviting && press < 0.02 && impact < 0.01
            ? MarsTicketSpec.ArrivalMotion.nudgeAmplitude
            : 0
        let towardInk = press * 40 + impact * 8
        return rest + fromAbove + invite + towardInk
    }

    private func pressGesture(punctuality: ArrivalPunctuality) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !reduceMotion, !locked else { return }
                inviting = false
                let dy = max(0, value.translation.height)
                press = min(1, dy / 88)
                if press > 0.82 {
                    commitStamp(punctuality: punctuality)
                }
            }
            .onEnded { value in
                guard !locked, impact < 1 else { return }
                let travel = hypot(value.translation.width, value.translation.height)
                // Tap or decisive downward press — same commit path.
                if travel < 14 || value.translation.height > 64 || press > 0.55 {
                    commitStamp(punctuality: punctuality)
                } else {
                    withAnimation(curve) {
                        press = 0
                    }
                    resumeInvite()
                }
            }
    }

    private func runEntrance() {
        enter = 0
        press = 0
        impact = 0
        exit = 0
        locked = false

        if reduceMotion {
            enter = 1
            return
        }

        withAnimation(MarsTicketSpec.ArrivalMotion.enter) {
            enter = 1
        }
        // Invite is the leftover of the entrance — same spring family, no new “mode”.
        Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(MarsTicketSpec.ArrivalMotion.enterMilliseconds)
            )
            resumeInvite()
        }
    }

    private func resumeInvite() {
        guard !locked, !reduceMotion, impact < 0.01 else { return }
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
        guard !locked else { return }
        locked = true
        inviting = false
        stampHaptic += 1

        // One continuous finish: press → ink → exit on the same downward arc.
        withAnimation(MarsTicketSpec.ArrivalMotion.slam) {
            press = 1
            impact = 1
        }

        Task { @MainActor in
            try? await Task.sleep(
                for: .milliseconds(MarsTicketSpec.ArrivalMotion.stampHoldMilliseconds)
            )
            if punctuality == .onTime || punctuality == .early {
                stampHaptic += 1
            }
            withAnimation(MarsTicketSpec.ArrivalMotion.exit) {
                exit = 1
            }
            try? await Task.sleep(
                for: .milliseconds(MarsTicketSpec.ArrivalMotion.exitMilliseconds)
            )
            onFinished?()
        }
    }

    private func accessibilityText(arrival: (title: String, minutes: Int, punctuality: ArrivalPunctuality)) -> String {
        let head = Punctuality.arrivalHeadline(arrival.punctuality)
        return "\(head)。\(arrival.title)。検札印を押してください"
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
    ArrivalInvalidateOverlay(
        moment: PunctualityMoment(
            kind: .arrival(
                title: "週次レビューの下書き",
                estimateSeconds: 1_500,
                actualSeconds: 1_440,
                punctuality: .onTime
            )
        )
    )
}
