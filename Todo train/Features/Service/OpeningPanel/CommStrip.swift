//
//  CommStrip.swift
//  Todo train
//
//  COMM の窓と TEST。キャップと RELAY・MAC の地は格子が描く。
//  往復の結果は保存しない。READY の条件には入れない。
//

import SwiftUI

enum OpeningPanelCommExchange: Equatable, Sendable {
    case unpaired
    case noRelay
    case noMac
    case reachedMac(milliseconds: Int)
    case legacyRelay(milliseconds: Int, macPresent: Bool)
}

struct OpeningPanelCommDisplay: Equatable {
    var text: String
    var relay: OpeningPanelLampStyle
    var mac: OpeningPanelLampStyle
    var failed: Bool
    var visible: Bool

    static let hidden = OpeningPanelCommDisplay(
        text: "",
        relay: .off,
        mac: .off,
        failed: false,
        visible: false
    )

    static let idle = OpeningPanelCommDisplay(
        text: "----",
        relay: .off,
        mac: .off,
        failed: false,
        visible: true
    )

    static let measuring = OpeningPanelCommDisplay(
        text: "MEAS…",
        relay: .off,
        mac: .off,
        failed: false,
        visible: true
    )
}

enum OpeningPanelCommLogic {
    /// 版 16 で ping・pong・echo を足した。それ未満の中継は hint だけを測る。
    static let controlContract = 16
    static let waitMilliseconds = 1500

    static func usesControlFrames(relayContract: Int) -> Bool {
        relayContract >= controlContract
    }

    /// `pong` も `echo` も、送ってから 1500ms を過ぎたものは届いていないものとして扱う。
    static func decide(
        pongMilliseconds: Int?,
        echoMilliseconds: Int?,
        echoMac: Bool?,
        waitMilliseconds: Int = waitMilliseconds
    ) -> OpeningPanelCommExchange {
        guard let pongMilliseconds, pongMilliseconds <= waitMilliseconds else {
            return .noRelay
        }
        guard
            let echoMilliseconds,
            echoMilliseconds <= waitMilliseconds,
            echoMac == true
        else {
            return .noMac
        }
        return .reachedMac(milliseconds: max(0, echoMilliseconds))
    }

    static func display(for exchange: OpeningPanelCommExchange) -> OpeningPanelCommDisplay {
        switch exchange {
        case .unpaired:
            return OpeningPanelCommDisplay(
                text: "NO PAIR",
                relay: .off,
                mac: .off,
                failed: true,
                visible: true
            )
        case .noRelay:
            return OpeningPanelCommDisplay(
                text: "NO RELAY",
                relay: .yellow,
                mac: .off,
                failed: true,
                visible: true
            )
        case .noMac:
            return OpeningPanelCommDisplay(
                text: "NO MAC",
                relay: .green,
                mac: .amber,
                failed: true,
                visible: true
            )
        case .reachedMac(let milliseconds):
            return OpeningPanelCommDisplay(
                text: timed("MAC", milliseconds: milliseconds),
                relay: .green,
                mac: .green,
                failed: false,
                visible: true
            )
        case .legacyRelay(let milliseconds, let macPresent):
            return OpeningPanelCommDisplay(
                text: timed("RELAY", milliseconds: milliseconds),
                relay: .green,
                mac: macPresent ? .green : .off,
                failed: false,
                visible: true
            )
        }
    }

    /// 3 桁で右に寄せる。1000 以上はそのまま出す。
    static func timed(_ label: String, milliseconds: Int) -> String {
        let digits = String(max(0, milliseconds))
        let pad = String(repeating: "\u{2007}", count: max(0, 3 - digits.count))
        return "\(label) \(pad)\(digits)MS"
    }
}

enum OpeningPanelCommMetrics {
    /// `#commW`。9px、`letter-spacing: .08em`、琥珀。
    static let fontSize: CGFloat = 9
    static let trackingEm: CGFloat = 0.08
    static let horizontalPadding: CGFloat = 6
}

@MainActor
@Observable
final class OpeningPanelCommModel {
    private(set) var display: OpeningPanelCommDisplay = .hidden
    private(set) var testing = false
    private var task: Task<Void, Never>?
    private var generation = 0

    func showIdle() {
        guard !testing, display == .hidden else { return }
        display = .idle
    }

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        testing = false
        display = .hidden
    }

    func start(
        measure: @escaping (@escaping () -> Void) async -> OpeningPanelCommExchange?,
        onRelay: @escaping () -> Void,
        onMac: @escaping () -> Void,
        onFailure: @escaping () -> Void
    ) {
        generation += 1
        let generation = generation
        task?.cancel()
        testing = true
        display = .measuring
        task = Task { @MainActor in
            var relayLit = false
            let exchange = await measure {
                guard !relayLit else { return }
                relayLit = true
                guard generation == self.generation else { return }
                self.display.relay = .green
                onRelay()
            }
            guard !Task.isCancelled, generation == self.generation, let exchange else { return }
            let next = OpeningPanelCommLogic.display(for: exchange)
            display = next
            testing = false
            if next.relay == .green, !relayLit {
                onRelay()
            }
            if next.mac == .green {
                onMac()
            }
            if next.failed {
                onFailure()
            }
        }
    }
}

struct OpeningPanelCommWindow: View {
    var text: String
    var visible: Bool

    var body: some View {
        Text(text)
            .font(.system(size: OpeningPanelCommMetrics.fontSize))
            .tracking(OpeningPanelCommMetrics.fontSize * OpeningPanelCommMetrics.trackingEm)
            .monospacedDigit()
            .foregroundStyle(OpeningPanelTokens.Palette.amber)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, OpeningPanelCommMetrics.horizontalPadding)
            .opacity(visible ? 1 : 0)
            .accessibilityLabel(text)
            .accessibilityHidden(!visible || text.isEmpty)
    }
}

struct OpeningPanelCommButton: View {
    var testing: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.clear
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .openingPanelAction(.commTest, perform: action)
        .accessibilityLabel("TEST")
        .accessibilityValue(testing ? "測定中" : "待機")
        .accessibilityHint("中継と Mac までの往復を測ります")
    }
}
