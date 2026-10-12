import SwiftUI
import TodoTrainSync

enum WatchCopy {
    static let idle = "乗車はありません。"
    static let remaining = "残り"
    static let overtime = "超過"
    static let paused = "停車"
    static let displayOnly = "約束の版が範囲外です。表示だけを続けます。"
    static let buildExplanation = "この Apple Watch に入っているアプリの作られた時点です。"
}

struct WatchRootView: View {
    var session: WatchPhoneSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = Int(context.date.timeIntervalSince1970)
            VStack(alignment: .leading, spacing: 8) {
                ride(at: now)
                if session.mirror.replyGate == .displayOnly {
                    Text(WatchCopy.displayOnly)
                        .font(.footnote)
                }
                build
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 4)
        .onAppear { session.activate() }
    }

    @ViewBuilder
    private func ride(at now: Int) -> some View {
        if let snap = session.mirror.snap, snap.phase != .idle {
            Text(snap.title ?? "")
                .font(.headline)
                .lineLimit(1)
            if snap.phase == .paused {
                Text(WatchCopy.paused)
                    .font(.caption)
                Text(clock(snap.remainingSeconds(at: now)))
                    .font(.title2.monospacedDigit())
            } else if snap.phase == .overtime {
                Text(WatchCopy.overtime)
                    .font(.caption)
                Text(clock(snap.remainingSeconds(at: now).map { abs($0) }))
                    .font(.title2.monospacedDigit())
            } else {
                Text(WatchCopy.remaining)
                    .font(.caption)
                Text(clock(snap.remainingSeconds(at: now)))
                    .font(.title2.monospacedDigit())
            }
        } else {
            Text(WatchCopy.idle)
        }
    }

    private var build: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BuildInfoCopy.title)
                .font(.caption2)
            Text(
                WatchBuildLine.line(
                    sha: BuildInfo.sha,
                    branch: BuildInfo.branch,
                    dirty: BuildInfo.dirty,
                    builtAt: BuildInfo.builtAt
                )
            )
            .font(.caption2)
            Text(WatchCopy.buildExplanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func clock(_ seconds: Int?) -> String {
        guard let seconds else { return "–" }
        let value = abs(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
