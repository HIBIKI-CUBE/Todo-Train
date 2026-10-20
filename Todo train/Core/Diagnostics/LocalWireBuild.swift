//
//  LocalWireBuild.swift
//  Todo train
//

import Foundation
import TodoTrainSync

enum LocalWireBuild {
    static var current: WireBuildInfo {
        WireBuildInfo(
            sha: BuildInfo.sha,
            dirty: BuildInfo.dirty,
            schema: StoreSchemaVersion.wire,
            builtAt: BuildInfo.builtAt
        )
    }

    static var line: String {
        BuildStamp.line(
            sha: BuildInfo.sha,
            branch: BuildInfo.branch,
            dirty: BuildInfo.dirty,
            builtAt: BuildInfo.builtAt,
            schemaMajor: StoreSchemaVersion.major
        )
    }
}
