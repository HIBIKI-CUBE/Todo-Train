import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import TodoTrainTicketUI

/// f20 signal inks. Dark-appearance TrainTheme values from the mock: rail, signalGreen, signalAmber.
enum ImaYaruInk {
    static let rail = Color(red: 115.0 / 255, green: 158.0 / 255, blue: 199.0 / 255)
    static let signalGreen = Color(red: 89.0 / 255, green: 199.0 / 255, blue: 133.0 / 255)
    static let signalAmber = Color(red: 255.0 / 255, green: 184.0 / 255, blue: 71.0 / 255)
    static let sheet = Color.black
    static let sheetEdge = Color(red: 44.0 / 255, green: 44.0 / 255, blue: 46.0 / 255)
    static let well = Color(red: 28.0 / 255, green: 28.0 / 255, blue: 30.0 / 255)

    static let railNS = NSColor(srgbRed: 115.0 / 255, green: 158.0 / 255, blue: 199.0 / 255, alpha: 1)
    static let signalGreenNS = NSColor(srgbRed: 89.0 / 255, green: 199.0 / 255, blue: 133.0 / 255, alpha: 1)
    static let signalAmberNS = NSColor(srgbRed: 255.0 / 255, green: 184.0 / 255, blue: 71.0 / 255, alpha: 1)
}

enum ImaYaruChoice: Equatable, Sendable {
    case depart
    case save
    case neutral
    case click
}

/// Cursor hit test. Origin is the press point. +x is right, +y is down (screen space).
/// Right sector is ±60° about east. Left sector is 120°…240° ( ±60° about west). The rest is neutral.
/// Under 8pt is a click. Inside the 30pt center, a drag is still neutral.
enum ImaYaruSectorHit {
    static let clickDistance: CGFloat = 8
    static let armDistance: CGFloat = 30
    static let halfAngle: CGFloat = 60

    static func choice(dx: CGFloat, dy: CGFloat) -> ImaYaruChoice {
        let distance = hypot(dx, dy)
        if distance < clickDistance { return .click }
        if distance < armDistance { return .neutral }
        let degrees = atan2(-dy, dx) * 180 / .pi
        let magnitude = abs(degrees)
        if magnitude <= halfAngle { return .depart }
        if magnitude >= 180 - halfAngle { return .save }
        return .neutral
    }
}

enum ImaYaruArm: Equatable, Sendable {
    case none
    case depart
    case save
    case blocked
}

/// Right slit is closed before service, and while a calendar event is the ride.
enum ImaYaruDepartGate: Equatable, Sendable {
    case open
    case beforeService
    case aboardCalendar

    static func resolve(serviceActive: Bool, timetableRide: Bool) -> ImaYaruDepartGate {
        if timetableRide { return .aboardCalendar }
        if !serviceActive { return .beforeService }
        return .open
    }

    var departEnabled: Bool { self == .open }

    var departLabel: String {
        switch self {
        case .open: "発車"
        case .beforeService: "運行前"
        case .aboardCalendar: "乗車中"
        }
    }
}

enum ImaYaruReleaseAction: Equatable, Sendable {
    case close
    case none
    case save
    case depart
    case deny
}

enum ImaYaruRelease {
    /// Pie release. A calendar ride saves from every sector. A short click still closes.
    static func resolve(
        choice: ImaYaruChoice,
        gate: ImaYaruDepartGate,
        canIssue: Bool
    ) -> ImaYaruReleaseAction {
        switch choice {
        case .click:
            return .close
        case .neutral:
            if gate == .aboardCalendar, canIssue { return .save }
            return .none
        case .save:
            return canIssue ? .save : .none
        case .depart:
            switch gate {
            case .open:
                return canIssue ? .depart : .none
            case .beforeService:
                return .deny
            case .aboardCalendar:
                return canIssue ? .save : .none
            }
        }
    }

    /// Horizontal flick release. A minutes stroke (no arm) sends nothing.
    static func resolve(
        arm: ImaYaruArm,
        gate: ImaYaruDepartGate,
        canIssue: Bool
    ) -> ImaYaruReleaseAction {
        switch arm {
        case .none:
            return .none
        case .save:
            return canIssue ? .save : .none
        case .blocked:
            return .deny
        case .depart:
            switch gate {
            case .open:
                return canIssue ? .depart : .none
            case .beforeService:
                return .deny
            case .aboardCalendar:
                return canIssue ? .save : .none
            }
        }
    }

    /// Return saves. ⌘Return departs, and saves when the right slit is closed.
    static func keyboard(
        commandReturn: Bool,
        gate: ImaYaruDepartGate,
        canIssue: Bool
    ) -> ImaYaruReleaseAction {
        guard canIssue else {
            if commandReturn, gate == .beforeService { return .deny }
            return .none
        }
        if !commandReturn { return .save }
        switch gate {
        case .open: return .depart
        case .beforeService, .aboardCalendar: return .save
        }
    }
}

/// Two-finger vertical stroke. Up (negative screen dy) raises the stop. f20 scale is 1.6.
enum ImaYaruMinutesStroke {
    static let scale: CGFloat = 1.6

    static func fingerFraction(
        anchorMinutes: Int,
        dy: CGFloat,
        padHeight: CGFloat,
        scale: CGFloat = ImaYaruMinutesStroke.scale
    ) -> CGFloat {
        let height = max(padHeight, 1)
        return EstimateSnapMapping.fraction(minutes: anchorMinutes) - dy / height * scale
    }

    /// Walks the sticky wells so one stroke can cross more than one stop.
    static func minutes(
        anchor: Int,
        dy: CGFloat,
        padHeight: CGFloat,
        scale: CGFloat = ImaYaruMinutesStroke.scale
    ) -> Int {
        let finger = fingerFraction(anchorMinutes: anchor, dy: dy, padHeight: padHeight, scale: scale)
        var current = anchor
        for _ in EstimateSnapMapping.stops {
            let scrub = EstimateSnapMapping.stickyScrub(
                fingerFraction: finger,
                anchoredMinutes: current
            )
            if scrub.anchoredMinutes == current { break }
            current = scrub.anchoredMinutes
        }
        return current
    }
}

enum ImaYaruStrokeAxis: Equatable, Sendable {
    case vertical
    case horizontal

    static let lockDistance: CGFloat = 10

    static func lock(dx: CGFloat, dy: CGFloat) -> ImaYaruStrokeAxis? {
        guard hypot(dx, dy) >= lockDistance else { return nil }
        return abs(dy) >= abs(dx) ? .vertical : .horizontal
    }
}

/// Horizontal flick. Right arms depart, left arms save. Threshold and hysteresis are the f20 defaults.
enum ImaYaruFlick {
    static let threshold: CGFloat = 70
    static let hysteresis: CGFloat = 0.85
    static let ratioOn: CGFloat = 2
    static let ratioOff: CGFloat = 1.6

    static func arm(
        dx: CGFloat,
        dy: CGFloat,
        current: ImaYaruArm,
        departEnabled: Bool
    ) -> ImaYaruArm {
        let ax = abs(dx)
        let ay = abs(dy)
        let dir: CGFloat = dx >= 0 ? 1 : -1
        let currentDir: CGFloat? = switch current {
        case .depart, .blocked: 1
        case .save: -1
        case .none: nil
        }
        var want: ImaYaruArm = current == .blocked ? .depart : current
        if current != .none, let currentDir {
            if dir != currentDir || ax < threshold * hysteresis || ax < ratioOff * ay {
                want = .none
            }
        }
        if want == .none, ax >= threshold, ax >= ratioOn * ay {
            want = dir > 0 ? .depart : .save
        }
        if want == .depart, !departEnabled { return .blocked }
        return want
    }

    static func charge(dx: CGFloat, dy: CGFloat) -> CGFloat {
        let ax = abs(dx)
        let ay = abs(dy)
        let heading = ax >= ratioOff * ay || ax >= threshold
        guard heading else { return 0 }
        return min(1.4, ax / threshold)
    }
}

/// Physical Mars face. 14-inch fallback matches the mock (425×288pt).
enum ImaYaruTicketMetrics {
    static let widthMM: CGFloat = MarsTicketSpec.aspectWidth
    static let heightMM: CGFloat = MarsTicketSpec.aspectHeight
    static let reference = CGSize(width: 425, height: 288)

    static func points(displayMillimeters: CGSize, displayPoints: CGSize) -> CGSize {
        guard displayMillimeters.width > 1, displayPoints.width > 1 else { return reference }
        let ptPerMM = displayPoints.width / displayMillimeters.width
        let width = widthMM * ptPerMM
        return CGSize(width: width, height: width * heightMM / widthMM)
    }

    static func points(on screen: NSScreen) -> CGSize {
        let millimeters = CGDisplayScreenSize(screen.overlayDisplayID)
        return points(
            displayMillimeters: CGSize(width: millimeters.width, height: millimeters.height),
            displayPoints: screen.frame.size
        )
    }
}

enum ImaYaruFollow {
    static let response: Double = 0.18
    static let damping: Double = 0.82
    static let maxTiltDegrees: Double = 2

    static func tilt(velocityX: CGFloat, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        let unit = max(-1, min(1, velocityX / 800))
        return Double(unit) * maxTiltDegrees
    }
}

/// f20 master timeline. machine 520 / feed 300 / exit 280, about 0.82s.
enum ImaYaruFlight {
    static let machineMs: Double = 520
    static let feedMs: Double = 300
    static let presentDwellMs: Double = 100
    static let exitMs: Double = 280
    static let presentEase: Double = 2
    static let exitPower: Double = 3
    static let machinePower: Double = 3
    static let machineDrift: Double = 0.15
    static let blinkHalfMs: Double = 70
    static let machineInMs: Double = 300
    static let waveSpacing: CGFloat = 110
    static let railGap: CGFloat = 5
    static let railSegments: Int = 64
    static let chevronCount: Int = 16
    static let chevronPitch: CGFloat = 9
    static let slotPush: CGFloat = 6
    static let lightSeconds: Double = 0.12

    static var presentEndMs: Double { feedMs + presentDwellMs }
    static var ticketDoneMs: Double { presentEndMs + exitMs }
    static var machineDoneMs: Double { feedMs + machineMs }

    static func smoother(_ value: Double) -> Double {
        let u = min(1, max(0, value))
        return u * u * u * (u * (u * 6 - 15) + 10)
    }

    static func clampUnit(_ value: Double) -> Double { min(1, max(0, value)) }

    static func presentAmount(_ tau: Double) -> Double {
        let u = clampUnit(tau / feedMs)
        return smoother(1 - pow(1 - u, presentEase))
    }

    static func exitAmount(_ tau: Double, power: Double) -> Double {
        pow(clampUnit((tau - presentEndMs) / exitMs), power)
    }

    /// Slot lamp in real time: on, off, on. Sharp, no blur.
    static func slotLamp(onAt elapsedMs: Double) -> Bool {
        if elapsedMs < 30 { return true }
        if elapsedMs < 30 + blinkHalfMs { return false }
        return true
    }
}

struct ImaYaruFlightGeometry: Equatable, Sendable {
    var ticketSize: CGSize
    var origin: CGPoint
    var destination: CGPoint
    /// How far the machine must travel to leave the screen.
    var machineClearance: CGFloat
    /// +1 departs to the right. −1 saves to the left.
    var direction: CGFloat
}

struct ImaYaruFlightFrame: Equatable, Sendable {
    var ticketCenter: CGPoint
    /// Signed shift of the machine, opposite the ticket. Returns to 0 after a save.
    var machineShift: CGFloat
    var printReveal: CGFloat
    /// 0 at the mouth, 1 when the rails have shrunk away.
    var catapultRetract: CGFloat
    /// 0…1 along the rail. The depart light rides with the ticket tip.
    var tip: CGFloat
    /// 1 feeding, 2 the short hold, 3 the ticket is leaving.
    var stage: Int
    var slotOn: Bool
    var finished: Bool
}

extension ImaYaruFlight {
    static func frame(tauMs: Double, geometry: ImaYaruFlightGeometry) -> ImaYaruFlightFrame {
        let tau = max(0, tauMs)
        let direction = geometry.direction >= 0 ? 1.0 : -1.0
        let width = Double(geometry.ticketSize.width)
        let depth = width + 20
        let drift = min(0.5, max(0, machineDrift))
        let head = depth * (1 - drift) + 4
        let present = presentAmount(tau)
        let leave = exitAmount(tau, power: exitPower)
        let leaveX = direction > 0 ? leave : exitAmount(tau, power: exitPower + 2)
        let originX = Double(geometry.origin.x)
        let originY = Double(geometry.origin.y)
        let landedX = originX + direction * head
        let ticketX = originX + direction * head * present + (Double(geometry.destination.x) - landedX) * leaveX
        let ticketY = originY + (Double(geometry.destination.y) - originY) * leave
        let clearance = Double(max(geometry.machineClearance, 1))
        let driftDistance = drift * depth
        let machine: Double
        if tau >= machineDoneMs {
            machine = clearance
        } else {
            let late = pow(clampUnit((tau - feedMs) / (machineDoneMs - feedMs)), machinePower)
            machine = driftDistance * smoother(tau / presentEndMs) + (clearance - driftDistance) * late
        }
        let traveled = max(0, direction * (ticketX - originX))
        let reveal = min(1, max(0, (machine + traveled) / depth))
        let retractSpan = (machineDoneMs - feedMs) * 0.9
        let retract = smoother(clampUnit((tau - feedMs) / retractSpan))
        let stage: Int
        if tau < feedMs {
            stage = 1
        } else if tau < presentEndMs {
            stage = 2
        } else {
            stage = 3
        }
        let tipTravel = max(head, 1)
        let tip = min(1, max(0, traveled / Double(tipTravel)))
        var shift = -direction * machine
        if direction < 0 {
            shift *= 1 - returnAmount(tauMs: tau)
        }
        return ImaYaruFlightFrame(
            ticketCenter: CGPoint(x: ticketX, y: ticketY),
            machineShift: shift,
            printReveal: reveal,
            catapultRetract: retract,
            tip: tip,
            stage: stage,
            slotOn: slotLamp(onAt: tau),
            finished: tau >= endMs(direction: direction)
        )
    }

    /// Save waits for the next machine to come back. Depart ends when the machine is off.
    static func endMs(direction: CGFloat) -> Double {
        if direction >= 0 { return machineDoneMs }
        return machineDoneMs + machineInMs
    }

    /// Machine return after a save. 0 is still offscreen, 1 is seated. Cubic ease-out.
    static func returnAmount(tauMs: Double) -> Double {
        let u = clampUnit((tauMs - machineDoneMs) / machineInMs)
        return 1 - pow(1 - u, 3)
    }
}

enum ImaYaruCatapult {
    static func clampUnit(_ value: CGFloat) -> CGFloat { min(1, max(0, value)) }

    static func wave(phase: Double, distance: CGFloat) -> CGFloat {
        var u = phase - Double(distance / ImaYaruFlight.waveSpacing)
        u -= floor(u)
        return CGFloat(pow(1 - u, 2.4))
    }

    static func segmentOpacity(
        index: Int,
        charge: CGFloat,
        retract: CGFloat,
        phase: Double,
        length: CGFloat,
        armed: Bool,
        launching: Bool,
        tip: CGFloat
    ) -> CGFloat {
        let count = CGFloat(ImaYaruFlight.railSegments)
        let dn = (CGFloat(index) + 0.5) / count
        let along = dn * length
        let distanceFade = max(0, 1 - dn * 0.97)
        let retractFade = clampUnit((1 - retract - dn) * count / 4 + 0.05)
        let wave = wave(phase: phase, distance: along)
        let body: CGFloat
        if launching {
            let gap = tip - dn
            if abs(gap) < 0.03 {
                body = 1
            } else if gap < 0 {
                body = 0.62
            } else {
                body = 0.95 * clampUnit(1 - gap / 0.45)
            }
        } else {
            let reach = clampUnit((charge - 0.04) / 0.7)
            let visible = clampUnit((reach - dn) * count / 4 + 0.05)
            if visible <= 0 { return 0 }
            if armed {
                body = min(0.9, 0.5 + 0.42 * wave) * visible
            } else {
                let gain = clampUnit((charge - 0.04) / 0.2)
                body = min(0.9, 0.2 + 0.62 * wave * gain) * visible
            }
        }
        return body * distanceFade * retractFade
    }

    /// Faint chevrons. Shape only — the same ink as the rail, never a hazard stripe.
    static func chevronOpacity(
        index: Int,
        charge: CGFloat,
        retract: CGFloat,
        phase: Double,
        length: CGFloat,
        armed: Bool,
        launching: Bool,
        tip: CGFloat
    ) -> CGFloat {
        let rail = segmentOpacity(
            index: min(index * 4, ImaYaruFlight.railSegments - 1),
            charge: charge,
            retract: retract,
            phase: phase,
            length: length,
            armed: armed,
            launching: launching,
            tip: tip
        )
        return min(0.26, rail * 0.34)
    }
}

extension NSEvent {
    /// Screen-style deltas for a two-finger stroke. Negative y is finger-up. Positive x is finger-right.
    func imaYaruStrokeDeltas() -> (dx: CGFloat, dy: CGFloat) {
        let reportedX = scrollingDeltaX
        let reportedY = scrollingDeltaY
        let deviceX = isDirectionInvertedFromDevice ? -reportedX : reportedX
        let deviceY = isDirectionInvertedFromDevice ? -reportedY : reportedY
        // Device +y is a swipe up, +x is a swipe left (NSEvent swipe signs).
        return (dx: -deviceX, dy: -deviceY)
    }
}

@MainActor
final class ImaYaruScrollBridge {
    var onScroll: ((CGFloat, CGFloat, NSEvent.Phase) -> Void)?
}
