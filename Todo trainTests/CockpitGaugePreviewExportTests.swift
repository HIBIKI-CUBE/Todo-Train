//
//  CockpitGaugePreviewExportTests.swift
//
//  Renders each Live Activity size so a PR can show the gauge.
//  Set COCKPIT_PREVIEW_DIR to write PNGs. The assertions only check that
//  ImageRenderer produced a bitmap.
//

import SwiftUI
import XCTest
@testable import Todo_train

@MainActor
final class CockpitGaugePreviewExportTests: XCTestCase {
    func testEachFaceRendersABitmap() throws {
        let now = Date()
        let riding = CockpitDisplayModel.session(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(12 * 60),
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: false,
            now: now
        )
        let paused = CockpitDisplayModel.session(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(12 * 60),
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: false,
            isPaused: true,
            now: now
        )
        let prompt = CockpitDisplayModel.session(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(12 * 60),
            budgetSeconds: 20 * 60,
            isOvertime: false,
            isStale: false,
            checkInPrompt: "まだ乗ってる？",
            now: now
        )
        let overtime = CockpitDisplayModel.session(
            title: "仕様書を書く",
            deadline: now.addingTimeInterval(-90),
            budgetSeconds: 20 * 60,
            isOvertime: true,
            isStale: false,
            now: now
        )
        let alert = CockpitDisplayModel(
            title: "仕様書を書く",
            clock: .alert,
            phase: .overtime,
            headerState: nil,
            deadlineLabel: "予定 —",
            budgetSeconds: 20 * 60,
            pausedProgress: 1,
            isStale: false,
            accessibilityTimer: "予定の時刻を過ぎています"
        )

        let shots: [(String, CGFloat, CGFloat, AnyView)] = [
            ("session-expanded-riding", 408, 160, face(riding, .expanded, .islandExpanded)),
            ("session-expanded-paused", 408, 160, face(paused, .expanded, .islandExpanded)),
            ("session-expanded-prompt", 408, 160, face(prompt, .expanded, .islandExpanded)),
            ("session-expanded-overtime", 408, 160, face(overtime, .expanded, .islandExpanded)),
            ("session-expanded-limited", 371, 160, face(riding, .expandedTight, .islandExpanded, limited: true)),
            ("session-lock", 408, 160, face(riding, .lockScreen, .lockScreen)),
            ("session-lock-paused", 408, 160, face(paused, .lockScreen, .lockScreen)),
            ("session-lock-compact", 408, 84, face(riding, .lockScreenCompact, .lockScreen)),
            ("session-standby", 408, 160, face(riding, .standBy, .standBy)),
            ("session-standby-paused", 408, 160, face(paused, .standBy, .standBy)),
            ("session-standby-prompt", 408, 160, face(prompt, .standBy, .standBy)),
            ("session-lock-prompt", 408, 160, face(prompt, .lockScreen, .lockScreen)),
            ("session-lock-overtime", 408, 160, face(overtime, .lockScreen, .lockScreen)),
            ("session-stack-small", 184, 72, face(riding, .stackSmall, .stack)),
            ("session-stack-small-paused", 184, 72, face(paused, .stackSmall, .stack)),
            ("session-stack-small-prompt", 184, 72, face(prompt, .stackSmall, .stack)),
            ("session-stack-small-overtime", 184, 72, face(overtime, .stackSmall, .stack)),
            ("session-stack-medium", 198, 140, face(riding, .stackMedium, .stack)),
            ("session-stack-medium-paused", 198, 140, face(paused, .stackMedium, .stack)),
            ("session-stack-medium-prompt", 198, 140, face(prompt, .stackMedium, .stack)),
            ("alarm-expanded-alert", 408, 160, face(alert, .expanded, .islandExpanded, stop: true)),
            ("session-compact", 210, 48, compactPair(riding, limited: false)),
            ("session-compact-limited", 180, 48, compactPair(riding, limited: true)),
            ("session-minimal", 45, 45, AnyView(ring(riding, diameter: 45))),
            ("session-minimal-overtime", 45, 45, AnyView(ring(overtime, diameter: 45))),
            ("focus-bar", 340, 28, AnyView(bar(progress: 0.45, phase: .cruise))),
            ("focus-bar-final", 340, 28, AnyView(bar(progress: 0.92, phase: .final))),
            ("focus-bar-overtime", 340, 28, AnyView(bar(progress: 1.12, phase: .overtime)))
        ]

        let dir = URL(fileURLWithPath: "/tmp/cockpit-gauge-previews", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for shot in shots {
            let data = try bitmap(shot.3, width: shot.1, height: shot.2)
            XCTAssertGreaterThan(data.count, 400, shot.0)
            try data.write(to: dir.appendingPathComponent("\(shot.0).png"))
        }
    }

    private func face(
        _ model: CockpitDisplayModel,
        _ metrics: CockpitFaceMetrics,
        _ surface: CockpitSafeSurface,
        limited: Bool = false,
        stop: Bool = false
    ) -> AnyView {
        AnyView(
            ZStack {
                Color(white: 0.22)
                CockpitSafeClipShape(surface: surface).fill(Color.black)
                CockpitActivityChrome(
                    model: model,
                    metrics: metrics,
                    surface: surface,
                    limitedWidth: limited,
                    rideButton: {
                        CockpitRoundButtonLabel(
                            systemImage: stop ? "stop.fill" : "pause.fill",
                            tint: stop ? CockpitColors.ink : CockpitColors.amber
                        )
                    },
                    resumeButton: {
                        CockpitReplyLabel(title: "再乗車", systemImage: "play.fill", tint: CockpitColors.green)
                    },
                    promptButtons: {
                        HStack(spacing: 4) {
                            CockpitReplyLabel(title: "続行", systemImage: "arrow.forward", tint: CockpitColors.green)
                            CockpitReplyLabel(title: "停車", systemImage: "pause.fill", tint: CockpitColors.amber)
                        }
                    }
                )
                CockpitSafeClipOverlay(surface: surface)
            }
            .environment(\.cockpitFrozenGaugeFraction, frozenFraction(model, now: Date()))
        )
    }

    private func compactPair(_ model: CockpitDisplayModel, limited: Bool) -> AnyView {
        let side = limited ? CGSize(width: 52.33, height: 36.67) : CockpitSizeContract.islandCompactSide
        return AnyView(
            HStack(spacing: 8) {
                pill(CockpitCompactLeadingGauge(model: model), size: side)
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().stroke(Color.white.opacity(0.7), lineWidth: 1))
                    .frame(width: 28, height: side.height)
                pill(
                    CockpitCompactTimer(
                        clock: model.clock,
                        phase: model.phase,
                        scheduledAt: model.scheduledAt,
                        limitedWidth: limited
                    ),
                    size: side
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.cockpitFrozenGaugeFraction, frozenFraction(model, now: Date()))
            .background(Color(white: 0.22))
        )
    }

    private func pill<V: View>(_ content: V, size: CGSize) -> some View {
        ZStack {
            CockpitSafeClipShape(surface: .islandCompact).fill(Color.black)
            CockpitSafeInset(surface: .islandCompact) { content }
            CockpitSafeClipOverlay(surface: .islandCompact)
        }
        .frame(width: size.width, height: size.height)
    }

    private func ring(_ model: CockpitDisplayModel, diameter: CGFloat) -> some View {
        ZStack {
            Color(white: 0.22)
            CockpitSafeClipShape(surface: .islandMinimal).fill(Color.black)
            CockpitSafeInset(surface: .islandMinimal) {
                CockpitRingGauge(model: model)
            }
            CockpitSafeClipOverlay(surface: .islandMinimal)
        }
        .environment(\.cockpitFrozenGaugeFraction, frozenFraction(model, now: Date()))
        .frame(width: diameter, height: diameter)
    }

    /// Same position the live `ProgressView(timerInterval:)` would draw. ImageRenderer does not tick.
    private func frozenFraction(_ model: CockpitDisplayModel, now: Date) -> Double {
        switch model.clock {
        case .countdown(let end):
            return CockpitGaugeRange.fractionAlongTrack(
                deadline: end,
                budgetSeconds: model.budgetSeconds,
                now: now
            )
        case .overtime, .alert:
            if let start = model.scheduledAt {
                return CockpitGaugeRange.fractionAlongTrack(
                    deadline: start,
                    budgetSeconds: model.budgetSeconds,
                    now: now
                )
            }
            return 1
        case .paused:
            return CockpitGaugeRange.trackFraction(progress: model.pausedProgress ?? 0)
        case .stale:
            return 0
        }
    }

    private func bar(progress: Double, phase: FocusTimerPhase) -> some View {
        FocusProgressBar(progress: progress, phase: phase, budgetSeconds: 20 * 60)
            .padding(.horizontal, 8)
            .background(Color.black)
    }

    private func bitmap<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> Data {
        let renderer = ImageRenderer(
            content: view.frame(width: width, height: height)
        )
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage, let data = image.pngData() else {
            XCTFail("ImageRenderer returned no bitmap")
            return Data()
        }
        return data
    }
}
