import Foundation

/// Budget-ratio countdown urgency. Shared by iOS Focus / Live Activity and Mac PiP.
public enum TimerUrgency: String, Equatable, Sendable {
    case cruise
    case approach
    case final
    case overtime

    public static func phase(remaining: TimeInterval, budgetSeconds: TimeInterval) -> TimerUrgency {
        if remaining < 0 { return .overtime }
        let budget = max(budgetSeconds, 1)
        let finalThreshold = max(budget * 0.10, 30)
        let approachThreshold = max(budget * 0.25, 90)
        if remaining <= finalThreshold { return .final }
        if remaining <= approachThreshold { return .approach }
        return .cruise
    }
}

public enum ClockTime {
    /// Absolute `m:ss` with no sign.
    public static func mmss(_ seconds: Int) -> String {
        let total = abs(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
