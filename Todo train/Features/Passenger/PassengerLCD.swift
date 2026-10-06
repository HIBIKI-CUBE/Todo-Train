//
//  PassengerLCD.swift
//  Todo train
//
//  ドア上の車内案内。状態帯は白い行先・縦の区切り・右上の時計。
//  下段の弧は自作。残り時間と予定時刻は運転中の計器と同じ桁。
//  乗る前の申し出は日常面なので、下部のシステムバナーに置く。
//

import SwiftUI

enum PassengerLCDPalette {
    /// 次はの情報面。切符の紙ではなく、冷たい白。
    static let face = Color(red: 0.965, green: 0.969, blue: 0.975)
    /// ただいまの下段。状態帯の下に分かれる補助面。
    static let lower = Color(red: 0.769, green: 0.776, blue: 0.788)
    static let ink = Color(red: 0.090, green: 0.094, blue: 0.102)
    static let strip = Color(red: 0.180, green: 0.282, blue: 0.420)
    static let passed = Color(red: 0.62, green: 0.625, blue: 0.635)
    static let bezel = Color(red: 0.086, green: 0.090, blue: 0.098)
    /// 状態帯を方面側と行先側に分ける縦棒。
    static let separator = Color(red: 0.74, green: 0.748, blue: 0.758)
    static let headerInk = Color.white
    static let headerMuted = Color.white.opacity(0.62)
    static let soonDigits = Color(red: 0.72, green: 0.38, blue: 0.08)
}

enum PassengerTimeRange {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    static func string(start: Date, end: Date) -> String {
        "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    static func clock(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

/// 次は画面の弧。駅名も号車も描かず、通過済みとこれからの位置だけを自作の曲線にする。
struct PassengerRouteArc: View {
    var progress: Double
    var showsDoor: Bool

    var body: some View {
        Canvas { context, size in
            let clamped = CGFloat(min(1, max(0, progress)))
            let width = max(9, min(14, size.shortestSide * 0.038))
            let path = Self.path(in: size, lineWidth: width)
            let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
            context.stroke(path, with: .color(PassengerLCDPalette.strip), style: style)
            let traveled = path.trimmedPath(from: 0, to: max(clamped, 0.001))
            if clamped > 0.004 {
                context.stroke(traveled, with: .color(PassengerLCDPalette.passed), style: style)
            }
            if let here = traveled.currentPoint {
                let radius = width * 0.85
                let dot = CGRect(x: here.x - radius, y: here.y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: dot), with: .color(PassengerLCDPalette.face))
                context.stroke(
                    Path(ellipseIn: dot),
                    with: .color(PassengerLCDPalette.ink),
                    lineWidth: max(2, width * 0.18)
                )
            }
            if showsDoor, let end = path.currentPoint {
                context.stroke(
                    Self.doorChevron(at: end, scale: width),
                    with: .color(PassengerLCDPalette.ink),
                    style: StrokeStyle(lineWidth: max(3, width * 0.34), lineCap: .round, lineJoin: .round)
                )
            }
        }
        .accessibilityLabel("区間の進み")
    }

    private static func path(in size: CGSize, lineWidth: CGFloat) -> Path {
        let pad = lineWidth
        let start = CGPoint(x: size.width - pad, y: pad)
        let end = CGPoint(x: pad, y: size.height - pad)
        let control = CGPoint(x: size.width - pad, y: size.height - pad)
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }

    private static func doorChevron(at end: CGPoint, scale: CGFloat) -> Path {
        let s = scale * 1.35
        var path = Path()
        path.move(to: CGPoint(x: end.x - s * 0.15, y: end.y - s))
        path.addLine(to: CGPoint(x: end.x + s * 0.95, y: end.y))
        path.addLine(to: CGPoint(x: end.x - s * 0.15, y: end.y + s))
        return path
    }
}

private extension CGSize {
    var shortestSide: CGFloat { min(width, height) }
}

struct PassengerDoorCock: View {
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(PassengerCopy.doorCock)
                .font(.system(size: 12, weight: .medium))
            Text(PassengerCopy.doorCockHint)
                .font(.system(size: 10, weight: .regular))
        }
        .foregroundStyle(PassengerLCDPalette.ink.opacity(0.42))
        .multilineTextAlignment(.trailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: PassengerLane.emergencyHold)
                .onEnded { _ in onOpen() }
        )
        .accessibilityLabel(PassengerCopy.doorCock)
        .accessibilityHint(PassengerCopy.doorCockHint)
        .accessibilityAddTraits(.isButton)
    }
}

private struct PassengerClock: ViewModifier {
    @Environment(SessionManager.self) private var sessionManager

    func body(content: Content) -> some View {
        content.task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                sessionManager.reconcile()
            }
        }
    }
}

/// 日常面の申し出。取り消しバナーと同じく下部のシステム素材。車内液晶の文法は使わない。
struct PassengerOfferInset: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        Group {
            switch sessionManager.passengerChrome {
            case .soon(let interval):
                PassengerHubSoon(interval: interval)
            case .offer(let interval, true):
                PassengerHubLate(interval: interval) {
                    sessionManager.boardPassenger()
                }
            case .offer(let interval, false):
                PassengerHubProminent(interval: interval) {
                    sessionManager.boardPassenger()
                }
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, TrainTheme.Space.lg)
        .modifier(PassengerClock())
    }
}

struct PassengerFocusBand: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        switch sessionManager.passengerChrome {
        case .soon(let interval):
            PassengerFocusSoon(interval: interval)
        case .offer(let interval, let collapsed):
            PassengerFocusOffer(interval: interval, collapsed: collapsed) {
                sessionManager.boardPassenger()
            }
        default:
            EmptyView()
        }
    }
}

struct PassengerCabinCover: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        Group {
            switch sessionManager.passengerChrome {
            case .aboard(let ride, let phrase, let progress):
                PassengerCabinScreen(
                    status: phrase.japanese,
                    english: phrase.english,
                    title: ride.title,
                    intervalStart: ride.intervalStart,
                    intervalEnd: ride.intervalEnd,
                    progress: progress,
                    showsDoorArrow: phrase == .soon,
                    showsCountdown: true,
                    onOpenDoor: { sessionManager.openEmergencyDoor() }
                )
            case .arrived(let ride):
                PassengerCabinScreen(
                    status: PassengerCopy.now,
                    english: PassengerCopy.nowEn,
                    title: ride.title,
                    intervalStart: ride.intervalStart,
                    intervalEnd: ride.intervalEnd,
                    progress: nil,
                    showsDoorArrow: false,
                    showsCountdown: false,
                    onOpenDoor: { sessionManager.openEmergencyDoor() }
                )
            case .doorOpened(let ride):
                PassengerCabinScreen(
                    status: PassengerCopy.doorOpened,
                    english: nil,
                    title: ride.title,
                    intervalStart: ride.intervalStart,
                    intervalEnd: ride.intervalEnd,
                    progress: nil,
                    showsDoorArrow: false,
                    showsCountdown: false,
                    onOpenDoor: { sessionManager.openEmergencyDoor() }
                )
            default:
                PassengerLCDPalette.bezel.ignoresSafeArea()
            }
        }
        .modifier(PassengerClock())
    }
}

/// ドア上液晶の画面割り。状態帯に白い行先と時計、下段に弧と残り時間。
struct PassengerCabinScreen: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var status: String
    var english: String?
    var title: String
    var intervalStart: Date?
    var intervalEnd: Date?
    var progress: Double?
    var showsDoorArrow: Bool
    var showsCountdown: Bool
    var onOpenDoor: () -> Void

    private var compact: Bool { verticalSizeClass == .compact }

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                GeometryReader { geo in
                    cabin(now: context.date, size: geo.size)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func cabin(now: Date, size: CGSize) -> some View {
        let headerHeight = min(
            max(size.height * (compact ? 0.34 : 0.26), compact ? 96 : 128),
            compact ? 150 : 188
        )
        return VStack(spacing: 0) {
            header(now: now, width: size.width, height: headerHeight)
            bodyField(now: now, size: CGSize(width: size.width, height: max(size.height - headerHeight, 1)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
        .background(PassengerLCDPalette.bezel.ignoresSafeArea())
        .animation(.easeOut(duration: 0.22), value: status)
    }

    private func header(now: Date, width: CGFloat, height: CGFloat) -> some View {
        let barWidth: CGFloat = 8
        let metaWidth = min(max(width * 0.20, 84), 104)
        let clockSize = min(height * 0.18, compact ? 22 : 32)
        let statusSize = min(height * 0.16, compact ? 16 : 22)
        let nameWidth = max(width - metaWidth - barWidth - clockSize * 2.4 - 28, 40)
        let name = fittedName(width: nameWidth, height: height)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                Text(status)
                    .font(.system(size: statusSize, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                if let english {
                    Text(english)
                        .font(.system(size: max(10, statusSize * 0.48), weight: .medium))
                        .foregroundStyle(PassengerLCDPalette.headerMuted)
                }
            }
            .padding(.leading, 16)
            .frame(width: metaWidth, alignment: .leading)

            Rectangle()
                .fill(PassengerLCDPalette.separator)
                .frame(width: barWidth)

            Text(title)
                .font(.system(size: name.size, weight: .black))
                .tracking(name.tracking)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityAddTraits(.isHeader)

            Text(PassengerTimeRange.clock(now))
                .font(.system(size: clockSize, weight: .medium))
                .monospacedDigit()
                .padding(.trailing, 16)
                .accessibilityLabel("現在時刻")
        }
        .foregroundStyle(PassengerLCDPalette.headerInk)
        .frame(width: width, height: height)
        .background(PassengerLCDPalette.bezel.ignoresSafeArea(edges: [.top, .horizontal]))
        .clipped()
        .accessibilityElement(children: .combine)
    }

    private func bodyField(now: Date, size: CGSize) -> some View {
        let arcSide = min(size.width * 0.52, size.height * 0.86)
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let progress {
                    PassengerRouteArc(progress: progress, showsDoor: showsDoorArrow)
                        .frame(width: arcSide, height: arcSide)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(.trailing, 18)
                        .padding(.bottom, 6)
                }
                if showsCountdown, let intervalEnd {
                    countdown(until: intervalEnd, now: now, columnWidth: size.width * 0.52)
                }
                if showsDoorArrow {
                    Text("開")
                        .font(.system(size: compact ? 16 : 20, weight: .bold))
                        .foregroundStyle(PassengerLCDPalette.ink.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 18)
                        .padding(.bottom, 12)
                        .accessibilityLabel("開扉")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsCountdown {
                HStack {
                    Spacer(minLength: 0)
                    PassengerDoorCock(onOpen: onOpenDoor)
                }
                .padding(.trailing, 12)
                .padding(.bottom, 6)
            }
        }
        .background(
            (showsCountdown ? PassengerLCDPalette.face : PassengerLCDPalette.lower)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func countdown(until end: Date, now: Date, columnWidth: CGFloat) -> some View {
        let remaining = end.timeIntervalSince(now)
        let digits = CockpitFormat.timerLabel(remaining: max(remaining, 0))
        let fontSize = min(columnWidth * 0.62, compact ? 72 : 108)
        return VStack(alignment: .leading, spacing: 2) {
            Text(digits)
                .font(.system(size: fontSize, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(showsDoorArrow ? PassengerLCDPalette.soonDigits : PassengerLCDPalette.ink)
                .minimumScaleFactor(0.35)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("残り時間")
                .accessibilityValue(CockpitFormat.accessibilityTimerValue(
                    remaining: remaining,
                    isStale: false,
                    isOvertime: false
                ))
            Text(CockpitFormat.deadlineLabel(remaining: max(remaining, 1), deadline: end))
                .font(.system(size: compact ? 13 : 15, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(PassengerLCDPalette.ink)
        }
        .padding(.leading, 16)
        .padding(.top, compact ? 12 : 24)
        .frame(width: columnWidth, alignment: .leading)
    }

    /// 一行に収まる範囲でだけ字間を開く。はみ出す字間は付けない。
    private func fittedName(width: CGFloat, height: CGFloat) -> (size: CGFloat, tracking: CGFloat) {
        let maxSize = min(height * 0.46, compact ? 48 : 76)
        let minSize: CGFloat = compact ? 22 : 28
        var size = maxSize
        while size > minSize {
            let tracking = trackingThatFits(size: size, width: width)
            if nameWidth(size: size, tracking: tracking) <= width {
                return (size, tracking)
            }
            size -= 1
        }
        return (minSize, 0)
    }

    private func trackingThatFits(size: CGFloat, width: CGFloat) -> CGFloat {
        let count = title.count
        guard count > 1 else { return 0 }
        let base = StationSignMetrics.nameTracking(title, compact: false)
        guard base > 0 else { return 0 }
        let wanted = min(base * (size / 32), size * 0.22)
        let gaps = CGFloat(count - 1)
        let room = width - CGFloat(count) * size
        guard room > 8 else { return 0 }
        return min(wanted, room / gaps)
    }

    private func nameWidth(size: CGFloat, tracking: CGFloat) -> CGFloat {
        let count = CGFloat(max(title.count, 1))
        return count * size + tracking * max(count - 1, 0)
    }
}

private struct PassengerHubChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: TrainTheme.Radius.control, style: .continuous)
        )
    }
}

private struct PassengerHubProminent: View {
    var interval: PassengerInterval
    var onBoard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: TrainTheme.Space.md) {
            VStack(alignment: .leading, spacing: TrainTheme.Space.xs) {
                Text(PassengerCopy.now)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(interval.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(PassengerTimeRange.string(start: interval.startsAt, end: interval.endsAt))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            Button(action: onBoard) {
                Text(PassengerCopy.board)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .accessibilityLabel(PassengerCopy.board)
        }
        .padding(TrainTheme.Space.lg)
        .modifier(PassengerHubChrome())
    }
}

private struct PassengerHubLate: View {
    var interval: PassengerInterval
    var onBoard: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: TrainTheme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(interval.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(PassengerCopy.boardLate)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            Button(action: onBoard) {
                Text(PassengerCopy.board)
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44)
                    .padding(.horizontal, TrainTheme.Space.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .accessibilityLabel(PassengerCopy.board)
        }
        .padding(.leading, TrainTheme.Space.lg)
        .padding(.trailing, TrainTheme.Space.md)
        .padding(.vertical, TrainTheme.Space.sm)
        .modifier(PassengerHubChrome())
    }
}

private struct PassengerHubSoon: View {
    var interval: PassengerInterval

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TrainTheme.Space.sm) {
            Text(PassengerCopy.soon)
                .font(.subheadline.weight(.semibold))
            Text(interval.title)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: TrainTheme.Space.sm)
            Text(PassengerTimeRange.string(start: interval.startsAt, end: interval.endsAt))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, TrainTheme.Space.lg)
        .padding(.vertical, TrainTheme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(PassengerHubChrome())
        .accessibilityElement(children: .combine)
    }
}

private struct PassengerFocusSoon: View {
    var interval: PassengerInterval

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TrainTheme.Space.sm) {
            Text(PassengerCopy.soon)
                .font(.system(size: 15, weight: .bold))
            Text(interval.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: TrainTheme.Space.sm)
            Text(PassengerTimeRange.string(start: interval.startsAt, end: interval.endsAt))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(FocusPanel.muted)
        }
        .modifier(PassengerFocusBandChrome())
        .accessibilityElement(children: .combine)
    }
}

private struct PassengerFocusOffer: View {
    var interval: PassengerInterval
    var collapsed: Bool
    var onBoard: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: TrainTheme.Space.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(collapsed ? PassengerCopy.boardLate : PassengerCopy.now)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(FocusPanel.muted)
                Text(interval.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onBoard) {
                Text(PassengerCopy.board)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, TrainTheme.Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(TrainTheme.rail)
            .accessibilityLabel(PassengerCopy.board)
        }
        .modifier(PassengerFocusBandChrome())
    }
}

private struct PassengerFocusBandChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(FocusPanel.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, TrainTheme.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FocusPanel.fill)
            .overlay(alignment: .bottom) {
                FocusControlDivider()
            }
    }
}

#Preview("乗車中") {
    PassengerCabinScreen(
        status: PassengerCopy.next,
        english: PassengerCopy.nextEn,
        title: "設計レビュー",
        intervalStart: Date(),
        intervalEnd: Date().addingTimeInterval(24 * 60 + 8),
        progress: 0.42,
        showsDoorArrow: false,
        showsCountdown: true,
        onOpenDoor: {}
    )
}

#Preview("まもなく") {
    PassengerCabinScreen(
        status: PassengerCopy.soon,
        english: PassengerCopy.soonEn,
        title: "定例",
        intervalStart: Date().addingTimeInterval(-20 * 60),
        intervalEnd: Date().addingTimeInterval(2 * 60 + 40),
        progress: 0.86,
        showsDoorArrow: true,
        showsCountdown: true,
        onOpenDoor: {}
    )
}

#Preview("ただいま") {
    PassengerCabinScreen(
        status: PassengerCopy.now,
        english: PassengerCopy.nowEn,
        title: "設計レビュー",
        intervalStart: Date().addingTimeInterval(-50 * 60),
        intervalEnd: Date(),
        progress: nil,
        showsDoorArrow: false,
        showsCountdown: false,
        onOpenDoor: {}
    )
}
