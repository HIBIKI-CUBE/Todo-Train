//
//  CockpitInstrumentViews.swift
//  Shared Live Activity instrument chrome (Focus dashboard echo).
//

import SwiftUI

// MARK: - Lock Screen / StandBy instrument

struct CockpitInstrumentPanel: View {
    let title: String
    let snapshot: CockpitInstrumentSnapshot
    var timerFontSize: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            CockpitHairline()
            timerRegion
            CockpitHairline()
            telemetryRegion
        }
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CockpitColors.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let state = snapshot.headerState {
                Text(state)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(snapshot.phase.accentColor)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CockpitColors.fill)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(snapshot.phase.accentColor)
                .frame(width: 3)
                .opacity(snapshot.phase == .cruise ? 0 : 1)
        }
    }

    private var timerRegion: some View {
        Text(CockpitFormat.timerLabel(remaining: snapshot.remaining))
            .font(.system(size: timerFontSize, weight: .semibold, design: .default))
            .monospacedDigit()
            .foregroundStyle(snapshot.phase.accentColor)
            .minimumScaleFactor(0.45)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black)
    }

    private var telemetryRegion: some View {
        VStack(spacing: 0) {
            CockpitProgressBar(progress: snapshot.progress, phase: snapshot.phase)
            HStack {
                Text(CockpitFormat.deadlineLabel(remaining: snapshot.remaining, deadline: snapshot.deadline))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(snapshot.phase == .overtime ? CockpitColors.red : CockpitColors.ink)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(CockpitColors.fill)
        }
    }
}

struct CockpitProgressBar: View {
    let progress: Double
    let phase: FocusTimerPhase

    private var clamped: Double { min(max(progress, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(CockpitColors.track)
                Rectangle()
                    .fill(phase.accentColor)
                    .frame(width: max(proxy.size.width * clamped, progress > 0 ? 2 : 0))
            }
        }
        .frame(height: 10)
    }
}

struct CockpitHairline: View {
    var body: some View {
        Rectangle()
            .fill(CockpitColors.hairline)
            .frame(height: 1)
    }
}

// MARK: - Alarm controls (gapless row)

#if canImport(AlarmKit) && canImport(ActivityKit)
import ActivityKit
import AlarmKit
import AppIntents

struct CockpitAlarmControlRow: View {
    let alarmID: UUID
    let sessionID: UUID
    let mode: AlarmPresentationState.Mode
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Button(intent: EndBellCancelIntent(alarmID: alarmID)) {
                CockpitControlCell(
                    title: "キャンセル",
                    systemImage: "xmark",
                    foreground: CockpitColors.muted,
                    fill: CockpitColors.fill,
                    compact: compact
                )
            }
            .buttonStyle(.plain)

            CockpitVerticalHairline()

            primaryAction
        }
        .background(CockpitColors.fill)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch mode {
        case .countdown:
            Button(intent: EndBellPauseIntent(alarmID: alarmID)) {
                CockpitControlCell(
                    title: "停車",
                    systemImage: "pause.fill",
                    foreground: CockpitColors.amber,
                    fill: CockpitColors.fillRaised,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
        case .paused:
            Button(intent: EndBellResumeIntent(alarmID: alarmID)) {
                CockpitControlCell(
                    title: "再乗車",
                    systemImage: "play.fill",
                    foreground: CockpitColors.ink,
                    fill: CockpitColors.fillRaised,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
        case .alert:
            Button(intent: EndBellStopIntent(alarmID: alarmID, sessionID: sessionID)) {
                CockpitControlCell(
                    title: "Stop",
                    systemImage: "stop.fill",
                    foreground: CockpitColors.ink,
                    fill: CockpitColors.fillRaised,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
        @unknown default:
            EmptyView()
        }
    }
}

private struct CockpitControlCell: View {
    let title: String
    let systemImage: String
    let foreground: Color
    let fill: Color
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 16 : 18, weight: .bold))
            Text(title)
                .font(.system(size: compact ? 15 : 17, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 10 : 14)
        .background(fill)
        .contentShape(Rectangle())
    }
}

private struct CockpitVerticalHairline: View {
    var body: some View {
        Rectangle()
            .fill(CockpitColors.hairline)
            .frame(width: 1)
    }
}
#endif
