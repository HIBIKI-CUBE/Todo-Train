//
//  TrainLayout.swift
//  Todo train
//
//  iPhone landscape (vertical size class compact) layout helpers.
//

import SwiftUI

enum TrainLayout {
    /// Left pane width for Hub landscape split (service + paused).
    static let hubServicePaneWidth: CGFloat = 280

    static func isCompactHeight(_ verticalSizeClass: UserInterfaceSizeClass?) -> Bool {
        verticalSizeClass == .compact
    }

    static func navigationBarTitleDisplayMode(
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> NavigationBarItem.TitleDisplayMode {
        isCompactHeight(verticalSizeClass) ? .inline : .large
    }
}

extension EnvironmentValues {
  /// True when vertical space is limited (e.g. iPhone landscape).
    var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }
}
