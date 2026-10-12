import Foundation
import TodoTrainSync

/// Mac does not build 予測の到着 and does not rewrite a ride's active time.
enum CompanionForecastExclusion {
    static func excludes(pauseInputSeconds: TimeInterval, activeSeconds: TimeInterval) -> Bool {
        ForecastExclusion.excludes(pauseInputSeconds: pauseInputSeconds, activeSeconds: activeSeconds)
    }
}
