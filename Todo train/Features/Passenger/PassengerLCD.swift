//
//  PassengerLCD.swift
//  Todo train
//
//  ドア上の車内案内。上帯＝状態・行先・時計、下帯＝残り・予定・横進捗。
//  殻は案内文法、桁は運転中の計器と同系。乗る前は下部バナー。
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

/// 区間の横一列進捗。通過済みグレー／これから路線色。
struct PassengerProgressStrip: View {
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = min(1, max(0, progress))
            let markX = min(max(width * clamped - 2, 0), max(width - 4, 0))
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(PassengerLCDPalette.passed)
                        .frame(width: width * clamped)
                    Rectangle()
                        .fill(PassengerLCDPalette.strip)
                        .frame(width: width * (1 - clamped))
                }
                Rectangle()
                    .fill(PassengerLCDPalette.ink)
                    .frame(width: 4, height: geo.size.height)
                    .offset(x: markX)
            }
        }
        .frame(height: 12)
        .accessibilityLabel("区間の進み")
    }
}

struct PassengerDoorArrow: View {
    var body: some View {
        HStack(spacing: 4) {
            Text("開")
                .font(.system(size: 15, weight: .bold))
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(PassengerLCDPalette.strip)
        .accessibilityLabel("開扉")
    }
}

struct PassengerDoorCock: View {
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(PassengerCopy.doorCock)
                .font(.system(size: 12, weight: .semibold))
            Text(PassengerCopy.doorCockHint)
                .font(.system(size: 10, weight: .regular))
        }
        .foregroundStyle(PassengerLCDPalette.ink.opacity(0.72))
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

/// ドア上液晶。上帯＝状態・行先・時計、下帯＝残り・予定・横進捗（円弧は使わない）。
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
        TimelineView(.periodic(from: .now, by: 1)) { context in
            GeometryReader { geo in
                lcdShell(now: context.date, size: geo.size)
            }
        }
        .background(PassengerLCDPalette.bezel.ignoresSafeArea())
        .animation(.easeOut(duration: 0.22), value: status)
    }

    private func lcdShell(now: Date, size: CGSize) -> some View {
        let verticalInset: CGFloat = compact ? 8 : 12
        let panelWidth = size.width
        let panelHeight = size.height - verticalInset * 2
        let upperHeight = min(max(panelHeight * 0.32, compact ? 68 : 84), compact ? 112 : 136)

        return VStack(spacing: 0) {
            Spacer(minLength: verticalInset)
            VStack(spacing: 0) {
                upperBand(now: now, width: panelWidth, height: upperHeight)
                Rectangle()
                    .fill(PassengerLCDPalette.ink.opacity(0.14))
                    .frame(height: 1)
                lowerBand(now: now, width: panelWidth, height: max(panelHeight - upperHeight - 1, 1))
            }
            .frame(width: panelWidth, height: panelHeight)
            .overlay {
                Rectangle()
                    .strokeBorder(Color.black.opacity(0.35), lineWidth: 2)
            }
            Spacer(minLength: verticalInset)
        }
        .frame(width: size.width, height: size.height)
    }

    private func upperBand(now: Date, width: CGFloat, height: CGFloat) -> some View {
        let statusWidth = min(max(height * 1.05, 72), 108)
        let clockSize = min(height * 0.22, compact ? 20 : 28)
        let statusSize = min(height * 0.2, compact ? 15 : 22)
        let titleSlot = max(width - statusWidth - 6 - clockSize * 2.8 - 36, 80)
        let name = fittedName(width: titleSlot, height: height)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(status)
                    .font(.system(size: statusSize, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                if let english {
                    Text(english)
                        .font(.system(size: max(9, statusSize * 0.45), weight: .medium))
                        .foregroundStyle(PassengerLCDPalette.headerMuted)
                }
            }
            .frame(width: statusWidth, alignment: .leading)
            .padding(.leading, 12)

            Rectangle()
                .fill(PassengerLCDPalette.separator.opacity(0.55))
                .frame(width: 6)

            Text(title)
                .font(.system(size: name.size, weight: .black))
                .tracking(name.tracking)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityAddTraits(.isHeader)

            Text(PassengerTimeRange.clock(now))
                .font(.system(size: clockSize, weight: .semibold))
                .monospacedDigit()
                .padding(.trailing, 12)
                .accessibilityLabel("現在時刻")
        }
        .foregroundStyle(PassengerLCDPalette.headerInk)
        .frame(width: width, height: height)
        .background(PassengerLCDPalette.bezel)
        .accessibilityElement(children: .combine)
    }

    private func lowerBand(now: Date, width: CGFloat, height: CGFloat) -> some View {
        let face = showsCountdown ? PassengerLCDPalette.face : PassengerLCDPalette.lower
        let footer: CGFloat = compact ? 52 : 58
        let stripBlock: CGFloat = progress == nil ? 0 : (compact ? 34 : 40)

        return VStack(spacing: 0) {
            if showsCountdown, let intervalEnd {
                countdownBlock(
                    until: intervalEnd,
                    now: now,
                    bandHeight: max(height - footer - stripBlock, 72)
                )
            } else {
                greetingBlock(bandHeight: max(height - footer, 72))
            }
            if let progress {
                progressRow(progress: progress)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            HStack {
                Spacer(minLength: 0)
                PassengerDoorCock(onOpen: onOpenDoor)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .frame(height: footer)
        }
        .frame(width: width, height: height)
        .background(face)
    }

    private func countdownBlock(until end: Date, now: Date, bandHeight: CGFloat) -> some View {
        let remaining = end.timeIntervalSince(now)
        let digits = CockpitFormat.timerLabel(remaining: max(remaining, 0))
        let timerHeight = max(bandHeight - 28, 64)

        return VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                Text(digits)
                    .font(.system(size: timerFontSize(in: geo.size), weight: .semibold, design: .default))
                    .monospacedDigit()
                    .foregroundStyle(showsDoorArrow ? PassengerLCDPalette.soonDigits : PassengerLCDPalette.ink)
                    .minimumScaleFactor(0.35)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: timerHeight)
            .accessibilityLabel("残り時間")
            .accessibilityValue(CockpitFormat.accessibilityTimerValue(
                remaining: remaining,
                isStale: false,
                isOvertime: false
            ))

            Text(CockpitFormat.deadlineLabel(remaining: max(remaining, 1), deadline: end))
                .font(.system(size: 15, weight: .semibold, design: .default))
                .monospacedDigit()
                .foregroundStyle(PassengerLCDPalette.ink)
        }
        .padding(.horizontal, 14)
        .padding(.top, compact ? 10 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func greetingBlock(bandHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let intervalStart, let intervalEnd {
                Text(PassengerTimeRange.string(start: intervalStart, end: intervalEnd))
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(PassengerLCDPalette.ink.opacity(0.72))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, compact ? 12 : 18)
        .frame(maxWidth: .infinity, minHeight: bandHeight * 0.5, alignment: .topLeading)
    }

    private func progressRow(progress: Double) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PassengerProgressStrip(progress: progress)
            if showsDoorArrow {
                PassengerDoorArrow()
            }
        }
    }

    private func timerFontSize(in size: CGSize) -> CGFloat {
        let byWidth = size.width * 0.48
        let byHeight = size.height * 0.72
        let capped: CGFloat = compact ? 140 : 220
        return min(byWidth, byHeight, capped)
    }

    private func fittedName(width: CGFloat, height: CGFloat) -> (size: CGFloat, tracking: CGFloat) {
        let maxSize = min(height * 0.42, compact ? 40 : 58)
        let minSize: CGFloat = compact ? 20 : 26
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
        let wanted = min(base * (size / 32), size * 0.2)
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
