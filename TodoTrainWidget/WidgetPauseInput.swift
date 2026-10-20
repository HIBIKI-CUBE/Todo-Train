import Foundation
import TodoTrainSync

/// The widget does not ask, and it does not measure input.
enum WidgetPauseInput {
    static func showsQuestion() -> Bool { false }
}
