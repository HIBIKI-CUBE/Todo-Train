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
    /// Title is missing. Both mouths stay closed, the same as a disabled depart.
    var needsTitle: Bool = false
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
    var machineOpacity: CGFloat = 1
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
                .opacity(picture.machineOpacity)
                .position(picture.machineCenter)
            if let catapult = picture.catapult, departLive {
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

    /// Depart mouth is open only when the gate allows it and the title is filled.
    private var departLive: Bool {
        picture.gate.departEnabled && !picture.needsTitle
    }

    private var machine: some View {
        let metrics = ImaYaruMachineMetrics.fitted(ticket: picture.ticketSize)
        let width = metrics.body.width
        let mouth = metrics.slotHeight
        let departPush: CGFloat = picture.arm == .depart && !picture.reduceMotion ? metrics.pt(ImaYaruFlight.slotPush) : 0
        let savePush: CGFloat = picture.arm == .save && !picture.reduceMotion ? -metrics.pt(ImaYaruFlight.slotPush) : 0
        let rubber = picture.arm == .blocked && !picture.reduceMotion ? picture.shake * metrics.pt(5) : 0
        return ZStack {
            card(metrics)
            ImaYaruSlit(
                kind: .save,
                width: metrics.slotWidth,
                height: mouth,
                scale: metrics.scale,
                charge: picture.arm == .save ? 1 : picture.saveCharge,
                lit: picture.arm == .save,
                dimmed: picture.needsTitle,
                lamp: picture.arm == .save ? picture.lamp : 0.35,
                on: picture.slotOn || picture.arm != .save
            )
            .offset(x: -width / 2 + metrics.slotWidth / 2 + savePush)
            .gesture(machineDrag)
            .accessibilityLabel(picture.needsTitle ? ImaYaruCopy.needsTitle : "保存")
            .accessibilityHint(picture.needsTitle ? ImaYaruCopy.needsTitleToIssue : "切符を発行します")

            ImaYaruSlit(
                kind: .depart,
                width: metrics.slotWidth,
                height: mouth,
                scale: metrics.scale,
                charge: departLive ? (picture.arm == .depart ? 1 : picture.departCharge) : 0,
                lit: picture.arm == .depart && departLive,
                dimmed: !departLive,
                lamp: departLive ? (picture.arm == .depart ? picture.lamp : 0.35) : 0.28,
                on: picture.slotOn || picture.arm != .depart
            )
            .offset(x: width / 2 - metrics.slotWidth / 2 + departPush + rubber)
            .gesture(machineDrag)
            .accessibilityLabel(departCaption)
            .accessibilityHint(departHint)

            if picture.arm == .save {
                ImaYaruOutlinedText(text: "保存", color: ImaYaruInk.signalAmber, size: metrics.pt(17))
                    .offset(x: -width / 2 - metrics.pt(48))
                    .allowsHitTesting(false)
            }
            if picture.needsTitle {
                outwardLabel(departCaption, color: ImaYaruInk.rail, metrics: metrics, rubber: rubber)
            } else if picture.arm == .depart || picture.arm == .blocked {
                ImaYaruOutlinedText(text: picture.gate.departLabel, color: departLabelColor, size: metrics.pt(17))
                    .offset(x: width / 2 + metrics.pt(56) + rubber)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: width + metrics.pt(220), height: metrics.body.height)
    }

    /// Long caption grows away from the mouth. Short labels stay centered on the rail.
    private func outwardLabel(
        _ text: String,
        color: Color,
        metrics: ImaYaruMachineMetrics,
        rubber: CGFloat
    ) -> some View {
        Color.clear
            .frame(width: 1, height: 1)
            .overlay(alignment: .leading) {
                ImaYaruOutlinedText(text: text, color: color, size: metrics.pt(17))
                    .fixedSize()
                    .padding(.leading, metrics.pt(4))
            }
            .offset(x: metrics.body.width / 2 + metrics.pt(16) + rubber)
            .allowsHitTesting(false)
    }

    private var departCaption: String {
        if picture.needsTitle { return ImaYaruCopy.needsTitle }
        return picture.gate.departLabel
    }

    private var departHint: String {
        if picture.needsTitle {
            return picture.gate.departEnabled ? ImaYaruCopy.needsTitleToDepart : ImaYaruCopy.needsTitleToIssue
        }
        switch picture.gate {
        case .open:
            return "切符を発行して発車します"
        case .beforeService:
            return "運行が始まってから発車できます"
        case .aboardCalendar:
            return "予定に乗っているあいだは発券だけできます"
        }
    }

    private var departLabelColor: Color {
        if !departLive { return ImaYaruInk.rail }
        if picture.arm == .depart { return ImaYaruInk.signalGreen }
        return ImaYaruInk.rail
    }

    private func card(_ metrics: ImaYaruMachineMetrics) -> some View {
        VStack(spacing: 0) {
            titleWell(metrics)
                .padding(.top, metrics.pt(14))
                .padding(.horizontal, metrics.pt(16))
            HStack(spacing: metrics.pt(16)) {
                HStack(alignment: .firstTextBaseline, spacing: metrics.pt(4)) {
                    Text("\(picture.minutes)")
                        .font(.system(size: metrics.pt(56), weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                    Text("分")
                        .font(.system(size: metrics.pt(20), weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                gauge(metrics)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, metrics.pt(12))
            .padding(.bottom, metrics.pt(12))
            .contentShape(Rectangle())
            .gesture(machineDrag)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("所要 \(picture.minutes) 分")
        }
        .frame(width: metrics.body.width, height: metrics.body.height)
        .background(ImaYaruInk.body, in: RoundedRectangle(cornerRadius: metrics.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
                .strokeBorder(ImaYaruInk.sheetEdge, lineWidth: metrics.pt(1))
        )
        .environment(\.colorScheme, .dark)
    }

    private func titleWell(_ metrics: ImaYaruMachineMetrics) -> some View {
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
        .font(.system(size: metrics.pt(17)))
        .foregroundStyle(.white)
        .padding(.horizontal, metrics.pt(12))
        .padding(.vertical, metrics.pt(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ImaYaruInk.well, in: RoundedRectangle(cornerRadius: metrics.pt(10), style: .continuous))
    }

    private func gauge(_ metrics: ImaYaruMachineMetrics) -> some View {
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule()
                .fill(ImaYaruInk.gauge)
                .frame(height: max(metrics.pt(8), CGFloat(picture.minutes) / 60 * metrics.pt(56)))
        }
        .frame(width: metrics.pt(10), height: metrics.pt(56))
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
    var width: CGFloat
    var height: CGFloat
    var scale: CGFloat
    var charge: CGFloat
    var lit: Bool
    var dimmed: Bool
    var lamp: CGFloat
    var on: Bool

    var body: some View {
        let ink = color
        let bar = max(0, min(1, charge)) * (height - 12 * scale)
        return ZStack {
            if dimmed {
                hatch
            } else {
                Capsule()
                    .fill(ink.opacity(0.14))
                    .frame(width: 3 * scale)
                    .padding(.vertical, 6 * scale)
                Capsule()
                    .fill(ink.opacity(on ? 1 : 0.22))
                    .frame(width: 3 * scale, height: max(3 * scale, bar))
                glyph(ink.opacity(0.9))
            }
        }
        .frame(width: width, height: height)
        .background(ImaYaruInk.sheet)
        .clipShape(slitShape)
        .overlay(slitShape.stroke(ink.opacity(dimmed ? 0.85 : 0.35 + 0.65 * lamp), lineWidth: 1.5 * scale))
    }

    /// Closed mouth. Horizontal rail stripes, the mock's hatch, in rail rather than gray.
    private var hatch: some View {
        let bandHeight = 2 * scale
        let step = 5 * scale
        return Canvas { context, size in
            let shade = GraphicsContext.Shading.color(ImaYaruInk.rail)
            var y: CGFloat = 0
            while y < size.height {
                let band = Path(CGRect(x: 0, y: y, width: size.width, height: bandHeight))
                context.fill(band, with: shade)
                y += step
            }
        }
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
        if dimmed {
            let radius = 3 * scale
            return UnevenRoundedRectangle(
                topLeadingRadius: radius,
                bottomLeadingRadius: radius,
                bottomTrailingRadius: radius,
                topTrailingRadius: radius
            )
        }
        switch kind {
        case .depart:
            return UnevenRoundedRectangle(
                topLeadingRadius: 4 * scale,
                bottomLeadingRadius: 4 * scale,
                bottomTrailingRadius: 1 * scale,
                topTrailingRadius: 1 * scale
            )
        case .save:
            return UnevenRoundedRectangle(
                topLeadingRadius: 1 * scale,
                bottomLeadingRadius: 1 * scale,
                bottomTrailingRadius: 4 * scale,
                topTrailingRadius: 4 * scale
            )
        }
    }

    private func glyph(_ ink: Color) -> some View {
        let scale = scale
        return Canvas { context, size in
            let shade = GraphicsContext.Shading.color(ink)
            let mid = size.height / 2
            let weight = 1.2 * scale
            switch kind {
            case .depart:
                for y in [mid - 6 * scale, mid + 6 * scale] {
                    var line = Path()
                    line.move(to: CGPoint(x: scale, y: y))
                    line.addLine(to: CGPoint(x: size.width - scale, y: y))
                    context.stroke(line, with: shade, lineWidth: weight)
                }
            case .save:
                var line = Path()
                line.move(to: CGPoint(x: scale, y: mid))
                line.addLine(to: CGPoint(x: size.width - 4 * scale, y: mid))
                context.stroke(line, with: shade, lineWidth: weight)
                let block = CGRect(x: size.width - 4 * scale, y: mid - 5 * scale, width: 3 * scale, height: 10 * scale)
                context.fill(Path(block), with: shade)
            }
        }
        .frame(width: 12 * scale, height: 24 * scale)
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
    var size: CGFloat = 17

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(color)
            .outlined(weight: max(1, size / 17))
            .fixedSize()
    }
}

private extension View {
    func outlined(weight: CGFloat = 1) -> some View {
        shadow(color: .black, radius: 0, x: -weight, y: 0)
            .shadow(color: .black, radius: 0, x: weight, y: 0)
            .shadow(color: .black, radius: 0, x: 0, y: -weight)
            .shadow(color: .black, radius: 0, x: 0, y: weight)
    }
}
