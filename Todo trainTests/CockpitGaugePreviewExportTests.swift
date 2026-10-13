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
            ("session-expanded-riding", 370, 150, face(riding, .expanded)),
            ("session-expanded-paused", 370, 150, face(paused, .expanded)),
            ("session-expanded-prompt", 370, 150, face(prompt, .expanded)),
            ("session-expanded-overtime", 370, 150, face(overtime, .expanded)),
            ("session-expanded-limited", 250, 120, face(riding, .expandedTight, limited: true)),
            ("session-lock", 398, 150, face(riding, .lockScreen)),
            ("session-lock-paused", 398, 150, face(paused, .lockScreen)),
            ("session-lock-compact", 398, 84, face(riding, .lockScreenCompact)),
            ("session-standby", 408, 160, face(riding, .standBy)),
            ("session-stack-small", 184, 72, face(riding, .stackSmall)),
            ("session-stack-small-paused", 184, 72, face(paused, .stackSmall)),
            ("session-stack-small-prompt", 184, 72, face(prompt, .stackSmall)),
            ("session-stack-small-overtime", 184, 72, face(overtime, .stackSmall)),
            ("session-stack-medium", 198, 140, face(riding, .stackMedium)),
            ("session-stack-medium-paused", 198, 140, face(paused, .stackMedium)),
            ("session-stack-medium-prompt", 198, 140, face(prompt, .stackMedium)),
            ("alarm-expanded-alert", 370, 150, face(alert, .expanded, stop: true)),
            ("session-compact", 160, 37, compact(riding, limited: false)),
            ("session-compact-limited", 120, 37, compact(riding, limited: true)),
            ("session-minimal", 45, 45, AnyView(ring(riding))),
            ("session-minimal-overtime", 45, 45, AnyView(ring(overtime))),
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
        limited: Bool = false,
        stop: Bool = false
    ) -> AnyView {
        AnyView(
            CockpitActivityChrome(
                model: model,
                metrics: metrics,
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
            .environment(\.cockpitFrozenGaugeFraction, frozenFraction(model, now: Date()))
            .background(Color.black)
        )
    }

    private func compact(_ model: CockpitDisplayModel, limited: Bool) -> AnyView {
        AnyView(
            HStack(spacing: 6) {
                CockpitTickGauge(model: model, limitedWidth: limited)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CockpitCompactTimer(
                    clock: model.clock,
                    phase: model.phase,
                    scheduledAt: model.scheduledAt,
                    limitedWidth: limited
                )
            }
            .padding(.horizontal, 6)
            .environment(\.cockpitFrozenGaugeFraction, frozenFraction(model, now: Date()))
            .background(Color.black)
        )
    }

    private func ring(_ model: CockpitDisplayModel) -> some View {
        CockpitRingGauge(model: model)
            .padding(4)
            .environment(\.cockpitFrozenGaugeFraction, frozenFraction(model, now: Date()))
            .background(Color.black)
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
