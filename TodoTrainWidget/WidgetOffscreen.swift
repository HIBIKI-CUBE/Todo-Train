import Foundation
import TodoTrainSync

/// The widget and Live Activity do not post the safety net. The phone and the Mac app do.
enum WidgetOffscreen {
    static func delivers(_ kind: OffscreenKind) -> Bool {
        _ = kind
        return false
    }
}
