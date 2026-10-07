import SwiftUI

private struct FocusZoomNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

public extension EnvironmentValues {
    /// Matched zoom source for an interrupt eject. iPhone Focus sets this. Mac leaves it nil.
    var focusZoomNamespace: Namespace.ID? {
        get { self[FocusZoomNamespaceKey.self] }
        set { self[FocusZoomNamespaceKey.self] = newValue }
    }
}
