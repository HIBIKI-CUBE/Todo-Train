import AppKit
import CoreGraphics
import Foundation
import TodoTrainSync

/// Last input age and whether the ride PiP is on screen.
/// Idle seconds come from `CGEventSource.secondsSinceLastEventType`. The event itself is not read.
/// Frontmost-app monitoring and Screen Time are not used.
struct MacPresenceSample: Equatable, Sendable {
    var pipVisible: Bool
    var attending: Bool
}

enum MacScreenLock {
    /// `screenIsUnlocked` ends in `Locked`, so a suffix check would treat unlock as lock.
    static func isLocked(notificationName: String) -> Bool? {
        switch notificationName {
        case "com.apple.screenIsLocked": true
        case "com.apple.screenIsUnlocked": false
        default: nil
        }
    }
}

enum MacInputIdle {
    static let eventTypes: [CGEventType] = [
        .keyDown,
        .flagsChanged,
        .leftMouseDown,
        .rightMouseDown,
        .otherMouseDown,
        .mouseMoved,
        .scrollWheel,
    ]

    static func secondsSinceLastInput(
        read: (CGEventSourceStateID, CGEventType) -> CFTimeInterval = CGEventSource.secondsSinceLastEventType
    ) -> TimeInterval {
        let samples = eventTypes.map { read(.combinedSessionState, $0) }
        return samples.min() ?? .greatestFiniteMagnitude
    }
}

extension CompanionMacRuntime {
    func startScreenLockObservation() {
        let center = DistributedNotificationCenter.default()
        let names = ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"]
        for name in names {
            let token = center.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] note in
                guard let locked = MacScreenLock.isLocked(notificationName: note.name.rawValue) else { return }
                Task { @MainActor in
                    self?.screenLocked = locked
                    self?.refreshMacPresence()
                }
            }
            presenceObservers.append(token)
        }
    }

    func refreshMacPresence() {
        guard isPaired, !presenceInFlight else { return }
        guard (peerContract?.contract ?? 3) >= (WireOp.presence.introducedIn ?? 5) else { return }
        let sample = MacPresenceSample(
            pipVisible: overlayPresentation.isVisible && !suppressRideOverlay,
            attending: NudgePlanner.macIsAttending(
                screenLocked: screenLocked || presence.systemAsleep || presence.screensAsleep,
                secondsSinceLastInput: MacInputIdle.secondsSinceLastInput()
            )
        )
        guard lastPresence != sample else { return }
        let previous = lastPresence
        lastPresence = sample
        presenceInFlight = true
        Task { [weak self] in
            let ok = await self?.sendPresence(sample) ?? false
            self?.presenceInFlight = false
            if !ok {
                self?.lastPresence = previous
            }
        }
    }

    func sendPresence(_ sample: MacPresenceSample) async -> Bool {
        guard isPaired else { return false }
        do {
            let command = CommandPlaintext(
                id: UUID(),
                op: .presence,
                sessionId: nil,
                at: now,
                build: LocalWireBuild.current,
                contract: ContractVersion.contract,
                minReadable: ContractVersion.minReadable,
                pipVisible: sample.pipVisible,
                attending: sample.attending
            )
            try await post(command)
            return true
        } catch {
            return false
        }
    }
}
