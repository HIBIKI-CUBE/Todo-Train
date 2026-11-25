import SwiftUI
import TodoTrainTicketUI

struct ImaYaruCatapultPicture: Equatable {
    var length: CGFloat
    var charge: CGFloat
    var retract: CGFloat
    var phase: Double
    var armed: Bool
    var launching: Bool
    var tip: CGFloat
}

struct ImaYaruStagePicture: Equatable {
    var ticketTitle: String
    var minutes: Int
    var gate: ImaYaruDepartGate
    var arm: ImaYaruArm
    var departCharge: CGFloat
    var saveCharge: CGFloat
    /// 0…1 lamp. Disabled depart stays dim.
    var lamp: CGFloat
    var slotOn: Bool
    var shake: CGFloat
    var ticketSize: CGSize
    var showTicket: Bool
    var ticketCenter: CGPoint
    var printReveal: CGFloat
    var tilt: Double
    var machineCenter: CGPoint
    /// Outer edge of the slit the ticket uses. Already includes the machine shift.
    var mouthX: CGFloat
    /// +1 depart, −1 save, 0 no clip.
    var flightDirection: CGFloat
    var catapult: ImaYaruCatapultPicture?
    var notice: String?
    var reduceMotion: Bool
    var stageSize: CGSize

    static let cardWidth: CGFloat = 300
    static let cardHeight: CGFloat = 168
}

struct ImaYaruStageView: View {
    @Binding var title: String
    var picture: ImaYaruStagePicture
    var interactive: Bool
    var titleFocused: FocusState<Bool>.Binding
    var onSubmitTitle: () -> Void
    var onMachineDrag: ((CGSize, Bool) -> Void)?
    var onBackgroundDrag: ((CGSize, Bool) -> Void)?

    var body: some View {
        let picture = picture
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(backgroundDrag)
            machine
                .position(picture.machineCenter)
            if let catapult = picture.catapult, picture.gate.departEnabled {
                ImaYaruCatapultCanvas(picture: catapult, ticketHeight: picture.ticketSize.height)
                    .position(x: picture.mouthX + catapult.length / 2, y: picture.machineCenter.y)
                    .allowsHitTesting(false)
            }
            if picture.showTicket {
                ticket
                    .position(picture.ticketCenter)
                    .allowsHitTesting(false)
            }
            if let notice = picture.notice {
                Text(notice)
                    .font(.callout)
                    .foregroundStyle(.white)
                    .outlined()
                    .multilineTextAlignment(.center)
                    .frame(width: 360)
                    .position(
                        x: picture.machineCenter.x,
                        y: picture.machineCenter.y + picture.ticketSize.height / 2 + 36
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: picture.stageSize.width, height: picture.stageSize.height, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private var ticket: some View {
        let size = picture.ticketSize
        let reveal = picture.printReveal
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                .fill(MarsTicketSpec.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: MarsTicketSpec.cornerRadius, style: .continuous)
                        .strokeBorder(MarsTicketSpec.printInk.opacity(0.18), lineWidth: 0.5)
                )
            MarsTicketView(
                content: MarsTicketContent(title: picture.ticketTitle, minutes: max(picture.minutes, 1)),
                titleReveal: 1
            )
            .frame(width: size.width, height: size.height)
            .mask(alignment: .top) {
                Rectangle().frame(height: max(0, size.height * reveal))
            }
        }
        .frame(width: size.width, height: size.height)
        .rotationEffect(.degrees(picture.tilt))
        .mask { mouthMask(size: size) }
        .accessibilityLabel("発券、\(picture.ticketTitle)、\(picture.minutes)分")
    }

    private func mouthMask(size: CGSize) -> some View {
        let localMouth = picture.mouthX - (picture.ticketCenter.x - size.width / 2)
        return Group {
            if picture.flightDirection > 0 {
                HStack(spacing: 0) {
                    Color.clear.frame(width: min(size.width, max(0, localMouth)))
                    Rectangle()
                }
            } else if picture.flightDirection < 0 {
                HStack(spacing: 0) {
                    Rectangle().frame(width: min(size.width, max(0, localMouth)))
                    Color.clear
                }
            } else {
                Rectangle()
            }
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
    }

    private var machine: some View {
        let width = ImaYaruStagePicture.cardWidth
        let ticketHeight = picture.ticketSize.height
        let departPush: CGFloat = picture.arm == .depart && !picture.reduceMotion ? ImaYaruFlight.slotPush : 0
        let savePush: CGFloat = picture.arm == .save && !picture.reduceMotion ? -ImaYaruFlight.slotPush : 0
        let rubber = picture.arm == .blocked && !picture.reduceMotion ? picture.shake * 5 : 0
        return ZStack {
            card
            ImaYaruSlit(
                kind: .save,
                height: ticketHeight,
                charge: picture.arm == .save ? 1 : picture.saveCharge,
                lit: picture.arm == .save,
                dimmed: false,
                lamp: picture.arm == .save ? picture.lamp : 0.35,
                on: picture.slotOn || picture.arm != .save
            )
            .offset(x: -width / 2 + 7 + savePush)
            .gesture(machineDrag)
            .accessibilityLabel("保存")
            .accessibilityHint("切符を発行します")

            ImaYaruSlit(
                kind: .depart,
                height: ticketHeight,
                charge: picture.gate.departEnabled ? (picture.arm == .depart ? 1 : picture.departCharge) : 0,
                lit: picture.arm == .depart && picture.gate.departEnabled,
                dimmed: !picture.gate.departEnabled,
                lamp: picture.gate.departEnabled ? (picture.arm == .depart ? picture.lamp : 0.35) : 0.28,
                on: picture.slotOn || picture.arm != .depart
            )
            .offset(x: width / 2 - 7 + departPush + rubber)
            .gesture(machineDrag)
            .accessibilityLabel(picture.gate.departLabel)
            .accessibilityHint(departHint)

            ImaYaruOutlinedText(text: "保存", color: ImaYaruInk.signalAmber.opacity(picture.arm == .save ? 1 : 0.7))
                .offset(x: -width / 2 - 48)
            ImaYaruOutlinedText(
                text: picture.gate.departLabel,
                color: departLabelColor
            )
            .offset(x: width / 2 + 56 + rubber)
        }
        .frame(width: width + 200, height: ticketHeight)
    }

    private var departHint: String {
        switch picture.gate {
        case .open:
            "切符を発行して発車します"
        case .beforeService:
            "運行が始まってから発車できます"
        case .aboardCalendar:
            "予定に乗っているあいだは発券だけできます"
        }
    }

    private var departLabelColor: Color {
        if !picture.gate.departEnabled { return Color.white.opacity(0.55) }
        if picture.arm == .depart { return ImaYaruInk.signalGreen }
        return ImaYaruInk.rail
    }

    private var card: some View {
        VStack(spacing: 0) {
            titleWell
                .padding(.top, 14)
                .padding(.horizontal, 16)
            HStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(picture.minutes)")
                        .font(.system(size: 56, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("分")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                gauge
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .contentShape(Rectangle())
            .gesture(machineDrag)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("所要 \(picture.minutes) 分")
        }
        .frame(width: ImaYaruStagePicture.cardWidth, height: ImaYaruStagePicture.cardHeight)
        .background(ImaYaruInk.sheet, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ImaYaruInk.sheetEdge, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }

    private var titleWell: some View {
        Group {
            if interactive {
                TextField("題名", text: $title, prompt: Text("題名").foregroundStyle(.white.opacity(0.45)))
                    .textFieldStyle(.plain)
                    .focused(titleFocused)
                    .onSubmit(onSubmitTitle)
            } else {
                Text(title.isEmpty ? "題名" : title)
                    .foregroundStyle(title.isEmpty ? Color.white.opacity(0.45) : Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .font(.system(size: 17))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ImaYaruInk.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var gauge: some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule()
                .fill(ImaYaruInk.rail)
                .frame(height: max(8, CGFloat(picture.minutes) / 60 * 56))
        }
        .frame(width: 10, height: 56)
        .accessibilityHidden(true)
    }

    private var machineDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onMachineDrag?(CGSize(width: value.translation.width, height: value.translation.height), false)
            }
            .onEnded { value in
                onMachineDrag?(CGSize(width: value.translation.width, height: value.translation.height), true)
            }
    }

    private var backgroundDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                onBackgroundDrag?(CGSize(width: value.translation.width, height: value.translation.height), false)
            }
            .onEnded { value in
                onBackgroundDrag?(CGSize(width: value.translation.width, height: value.translation.height), true)
            }
    }
}

private struct ImaYaruSlit: View {
    enum Kind { case depart, save }

    var kind: Kind
    var height: CGFloat
    var charge: CGFloat
    var lit: Bool
    var dimmed: Bool
    var lamp: CGFloat
    var on: Bool

    var body: some View {
        let ink = color
        let bar = max(0, min(1, charge)) * (height - 12)
        return ZStack {
            Capsule()
                .fill(ink.opacity(dimmed ? 0.16 : 0.14))
                .frame(width: 3)
                .padding(.vertical, 6)
            Capsule()
                .fill(ink.opacity(on ? 1 : 0.22))
                .frame(width: 3, height: max(3, bar))
            glyph(ink.opacity(dimmed ? 0.45 : 0.9))
        }
        .frame(width: 14, height: height)
        .background(ImaYaruInk.sheet)
        .clipShape(slitShape)
        .overlay(slitShape.stroke(ink.opacity(0.35 + 0.65 * lamp), lineWidth: 1.5))
        .opacity(dimmed ? 0.55 : 1)
    }

    private var color: Color {
        // 発車側の口は溜めも ready も rail のまま。緑に切り替わるのは誘導レールと「発車」。
        if dimmed { return ImaYaruInk.rail }
        switch kind {
        case .save: return ImaYaruInk.signalAmber
        case .depart: return ImaYaruInk.rail
        }
    }

    private var slitShape: UnevenRoundedRectangle {
        switch kind {
        case .depart:
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 4, bottomTrailingRadius: 1, topTrailingRadius: 1)
        case .save:
            UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 1, bottomTrailingRadius: 4, topTrailingRadius: 4)
        }
    }

    private func glyph(_ ink: Color) -> some View {
        Canvas { context, size in
            let shade = GraphicsContext.Shading.color(ink)
            let mid = size.height / 2
            switch kind {
            case .depart:
                for y in [mid - 6, mid + 6] {
                    var line = Path()
                    line.move(to: CGPoint(x: 1, y: y))
                    line.addLine(to: CGPoint(x: size.width - 1, y: y))
                    context.stroke(line, with: shade, lineWidth: 1.2)
                }
            case .save:
                var line = Path()
                line.move(to: CGPoint(x: 1, y: mid))
                line.addLine(to: CGPoint(x: size.width - 4, y: mid))
                context.stroke(line, with: shade, lineWidth: 1.2)
                let block = CGRect(x: size.width - 4, y: mid - 5, width: 3, height: 10)
                context.fill(Path(block), with: shade)
            }
        }
        .frame(width: 12, height: 24)
    }
}

struct ImaYaruCatapultCanvas: View {
    var picture: ImaYaruCatapultPicture
    var ticketHeight: CGFloat

    var body: some View {
        let gap = ImaYaruFlight.railGap
        let height = ticketHeight + gap * 2
        Canvas { context, _ in
            let length = picture.length
            let count = ImaYaruFlight.railSegments
            let segment = length / CGFloat(count)
            let ink = (picture.armed || picture.launching) ? ImaYaruInk.signalGreen : ImaYaruInk.rail
            for index in 0..<count {
                let alpha = ImaYaruCatapult.segmentOpacity(
                    index: index,
                    charge: picture.charge,
                    retract: picture.retract,
                    phase: picture.phase,
                    length: length,
                    armed: picture.armed,
                    launching: picture.launching,
                    tip: picture.tip
                )
                guard alpha > 0.01 else { continue }
                let x = CGFloat(index) * segment
                let rail = Path(CGRect(x: x, y: 0, width: segment + 0.6, height: 2))
                let lower = Path(CGRect(x: x, y: height - 2, width: segment + 0.6, height: 2))
                context.fill(rail, with: .color(ink.opacity(alpha)))
                context.fill(lower, with: .color(ink.opacity(alpha)))
                if index % 2 == 0 {
                    let scan = Path(CGRect(x: x, y: 4, width: segment, height: 1))
                    let scanLower = Path(CGRect(x: x, y: height - 5, width: segment, height: 1))
                    context.fill(scan, with: .color(ink.opacity(alpha * 0.35)))
                    context.fill(scanLower, with: .color(ink.opacity(alpha * 0.35)))
                }
            }
            let chevronHeight = ticketHeight * 0.8
            let thickness = chevronHeight * 0.2
            let head = chevronHeight * 0.3
            let pitch = thickness * 1.8
            let midY = height / 2
            for index in 0..<ImaYaruFlight.chevronCount {
                let origin = 14 + CGFloat(index) * pitch
                guard origin + thickness + head <= length - 4 else { continue }
                let alpha = ImaYaruCatapult.chevronOpacity(
                    index: index,
                    charge: picture.charge,
                    retract: picture.retract,
                    phase: picture.phase,
                    length: length,
                    armed: picture.armed,
                    launching: picture.launching,
                    tip: picture.tip
                )
                guard alpha > 0.01 else { continue }
                var path = Path()
                let top = midY - chevronHeight / 2
                path.move(to: CGPoint(x: origin, y: top))
                path.addLine(to: CGPoint(x: origin + thickness, y: top))
                path.addLine(to: CGPoint(x: origin + thickness + head, y: midY))
                path.addLine(to: CGPoint(x: origin + thickness, y: top + chevronHeight))
                path.addLine(to: CGPoint(x: origin, y: top + chevronHeight))
                path.addLine(to: CGPoint(x: origin + head, y: midY))
                path.closeSubpath()
                context.fill(path, with: .color(ink.opacity(alpha)))
            }
        }
        .frame(width: picture.length, height: height)
        .allowsHitTesting(false)
    }
}

struct ImaYaruOutlinedText: View {
    var text: String
    var color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(color)
            .outlined()
            .fixedSize()
    }
}

private extension View {
    func outlined() -> some View {
        shadow(color: .black, radius: 0, x: -1, y: 0)
            .shadow(color: .black, radius: 0, x: 1, y: 0)
            .shadow(color: .black, radius: 0, x: 0, y: -1)
            .shadow(color: .black, radius: 0, x: 0, y: 1)
    }
}
