//
//  BuildInfoTests.swift
//  TodoTrainCompanionTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import TodoTrainCompanion

@MainActor
struct CompanionBuildInfoTests {
    @Test func schemaVersionFollowsTheContainer() {
        #expect(StoreSchemaVersion.current == AppModelContainer.schema.version)
        #expect(LocalWireBuild.current.schema == StoreSchemaVersion.wire)
    }

    @Test func menuLineUsesEmbeddedStamp() {
        if BuildInfo.sha == "unknown" {
            #expect(LocalWireBuild.line == "記録なし")
        } else {
            #expect(LocalWireBuild.line.contains(BuildInfo.sha))
            #expect(LocalWireBuild.line.contains("版 \(StoreSchemaVersion.major)"))
        }
    }
}
