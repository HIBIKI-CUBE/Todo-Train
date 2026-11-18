//
//  RunStatusNowDisplay.swift
//  Todo train
//
//  ただいま板と DEPART 横の行で共有する札・文言。
//

import SwiftUI

enum RunStatusNowChipKind: Equatable {
    case beforeStart
    case normal
    case dense
    case hold
}

enum RunStatusNowLayout {
    case nowBoard
    case departLine
}

enum RunStatusNowDisplayModel: Equatable {
    case ridingNormal(remainingMinutes: Int, until: String)
    case waiting(
        chip: RunStatusNowChipKind,
        statusTitle: String,
        minutesUntilNormal: Int,
        nextNormalDurationMinutes: Int
    )
    case endedTodayNormal(chip: RunStatusNowChipKind, statusTitle: String)
    case serviceEnded
}

extension RunStatusNow {
    func displayModel(calendar: Calendar) -> RunStatusNowDisplayModel {
        switch caseKind {
        case .ridingNormal(let remainingMinutes, let endsAt):
            return .ridingNormal(
                remainingMinutes: remainingMinutes,
                until: RunStatusLogic.formatUntil(endsAt, calendar: calendar)
            )
        case .beforeStart(let untilNormal, let thenLength):
            return .waiting(
                chip: .beforeStart,
                statusTitle: RunStatusNowCopy.beforeStart,
                minutesUntilNormal: untilNormal,
                nextNormalDurationMinutes: thenLength
            )
        case .waitingForNormal(let status, let untilNormal, let thenLength):
            return .waiting(
                chip: chipKind(for: status),
                statusTitle: shortStatusTitle(for: status),
                minutesUntilNormal: untilNormal,
                nextNormalDurationMinutes: thenLength
            )
        case .afterLastNormal(let status):
            return .endedTodayNormal(
                chip: chipKind(for: status),
                statusTitle: shortStatusTitle(for: status)
            )
        case .afterRangeEnd:
            return .serviceEnded
        }
    }

    private func chipKind(for status: RunStatusKind) -> RunStatusNowChipKind {
        switch status {
        case .normal:
            return .normal
        case .dense:
            return .dense
        case .hold:
            return .hold
        }
    }

    private func shortStatusTitle(for status: RunStatusKind) -> String {
        switch status {
        case .normal:
            return RunStatusNowCopy.normalShort
        case .dense:
            return RunStatusNowCopy.denseShort
        case .hold:
            return RunStatusNowCopy.holdShort
        }
    }
}

enum RunStatusNowCopy {
    static let beforeStart = "始発前"
    static let normalLong = "平常運転"
    static let normalShort = "平常"
    static let denseShort = "過密"
    static let holdShort = "見合せ"
    static let after = "あと"
    static let untilNormal = "平常運転まで"
    static let thenFrom = "そこから"
    static let untilSuffix = "まで"
    static let normalEndedToday = "本日の平常運転は終了"
    static let serviceEndedToday = "本日の運転終了"
}

struct RunStatusNowStatusChip: View {
    var kind: RunStatusNowChipKind
    var layout: RunStatusNowLayout

    private var size: CGSize {
        switch layout {
        case .nowBoard:
            return OpeningPanelTokens.RunStatusChrome.nowChipSize
        case .departLine:
            return OpeningPanelTokens.RunStatusChrome.departChipSize
        }
    }

    var body: some View {
        Group {
            switch kind {
            case .beforeStart:
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Color.clear)
            case .normal:
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(OpeningPanelTokens.Palette.amberDim)
            case .dense:
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(OpeningPanelTokens.RunStatusChrome.denseStripeBackground)
            case .hold:
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(OpeningPanelTokens.RunStatusChrome.holdFace)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay { edgeOverlay }
        .overlay { denseOverlay }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var edgeOverlay: some View {
        switch kind {
        case .beforeStart:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .strokeBorder(OpeningPanelTokens.RunStatusChrome.preEdge, lineWidth: 1)
        case .hold:
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .strokeBorder(OpeningPanelTokens.RunStatusChrome.holdEdge, lineWidth: 1)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var denseOverlay: some View {
        if kind == .dense {
            RunStatusDenseStripeFill()
                .clipShape(RoundedRectangle(cornerRadius: 1, style: .continuous))
        }
    }
}

private struct RunStatusDenseStripeFill: View {
    var body: some View {
        GeometryReader { geo in
            let step: CGFloat = 4
            let stroke = OpeningPanelTokens.RunStatusChrome.denseStripe
            Canvas { context, size in
                var x: CGFloat = -size.height
                while x < size.width + size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: .color(stroke), lineWidth: 2)
                    x += step
                }
            }
        }
    }
}

struct RunStatusNowReadingLine: View {
    var model: RunStatusNowDisplayModel
    var layout: RunStatusNowLayout
    var isLit: Bool

    var body: some View {
        Group {
            if isLit {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .opacity(isLit ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: layout == .nowBoard ? 4 : 4) {
            switch model {
            case .ridingNormal(let remaining, let until):
                RunStatusNowStatusChip(kind: .normal, layout: layout)
                statusName(RunStatusNowCopy.normalLong)
                if layout == .nowBoard {
                    Spacer(minLength: 0)
                }
                caption(RunStatusNowCopy.after)
                primaryNumber(remaining)
                untilLine(until)
            case .waiting(let chip, let title, let untilNormal, let thenLength):
                RunStatusNowStatusChip(kind: chip, layout: layout)
                statusName(title)
                if layout == .nowBoard {
                    Spacer(minLength: 0)
                }
                caption(RunStatusNowCopy.untilNormal)
                primaryNumber(untilNormal)
                caption(RunStatusNowCopy.thenFrom)
                secondaryNumber(thenLength)
            case .endedTodayNormal(let chip, let title):
                RunStatusNowStatusChip(kind: chip, layout: layout)
                statusName(title)
                if layout == .nowBoard {
                    Spacer(minLength: 0)
                }
                caption(RunStatusNowCopy.normalEndedToday)
            case .serviceEnded:
                statusName(RunStatusNowCopy.serviceEndedToday)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func statusName(_ text: String) -> some View {
        Text(text)
            .font(statusFont)
            .fontWeight(.semibold)
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
    }

    @ViewBuilder
    private func caption(_ text: String) -> some View {
        Text(text)
            .font(captionFont)
            .foregroundStyle(OpeningPanelTokens.Palette.legend.opacity(0.75))
    }

    @ViewBuilder
    private func primaryNumber(_ minutes: Int) -> some View {
        Text(RunStatusLogic.formatHM(minutes))
            .font(numberFont(primary: true))
            .fontWeight(.semibold)
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
    }

    @ViewBuilder
    private func secondaryNumber(_ minutes: Int) -> some View {
        Text(RunStatusLogic.formatHM(minutes))
            .font(numberFont(primary: false))
            .fontWeight(.semibold)
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
    }

    @ViewBuilder
    private func untilLine(_ until: String) -> some View {
        HStack(spacing: 0) {
            Text(until)
                .font(numberFont(primary: false))
                .fontWeight(.semibold)
                .foregroundStyle(OpeningPanelTokens.Palette.amber)
            Text(RunStatusNowCopy.untilSuffix)
                .font(captionFont)
                .foregroundStyle(OpeningPanelTokens.Palette.legend.opacity(0.75))
        }
    }

    private var statusFont: Font {
        switch layout {
        case .nowBoard:
            return .system(size: OpeningPanelTokens.TypeSize.nowStatus, weight: .semibold)
        case .departLine:
            return .system(size: OpeningPanelTokens.TypeSize.departLine, weight: .semibold)
        }
    }

    private var captionFont: Font {
        let size = layout == .nowBoard ? OpeningPanelTokens.TypeSize.caption : OpeningPanelTokens.TypeSize.departLine
        return .system(size: size)
    }

    private func numberFont(primary: Bool) -> Font {
        switch layout {
        case .nowBoard:
            let size = primary ? OpeningPanelTokens.TypeSize.nowPrimary : OpeningPanelTokens.TypeSize.nowSecondary
            return .system(size: size, weight: .semibold, design: .monospaced)
        case .departLine:
            return .system(size: OpeningPanelTokens.TypeSize.departLine, weight: .semibold, design: .monospaced)
        }
    }

    private var accessibilityText: String {
        switch model {
        case .ridingNormal(let remaining, let until):
            return "\(RunStatusNowCopy.normalLong) \(RunStatusNowCopy.after) \(RunStatusLogic.formatHM(remaining)) \(until)\(RunStatusNowCopy.untilSuffix)"
        case .waiting(_, let title, let untilNormal, let thenLength):
            return "\(title) \(RunStatusNowCopy.untilNormal) \(RunStatusLogic.formatHM(untilNormal)) \(RunStatusNowCopy.thenFrom) \(RunStatusLogic.formatHM(thenLength))"
        case .endedTodayNormal(_, let title):
            return "\(title) \(RunStatusNowCopy.normalEndedToday)"
        case .serviceEnded:
            return RunStatusNowCopy.serviceEndedToday
        }
    }
}