//
//  BuildInfoTests.swift
//  Todo trainTests
//

import Foundation
import SwiftData
import Testing
import TodoTrainSync
@testable import Todo_train

@MainActor
struct BuildInfoTests {
    @Test func schemaVersionFollowsTheContainer() {
        #expect(StoreSchemaVersion.current == AppModelContainer.schema.version)
        #expect(LocalWireBuild.current.schema == StoreSchemaVersion.wire)
        let version = AppModelContainer.schema.version
        #expect(StoreSchemaVersion.major == version.major)
        #expect(StoreSchemaVersion.wire == "\(version.major).\(version.minor).\(version.patch)")
    }

    @Test func embeddedSHAIsSevenCharactersOrUnrecorded() {
        #expect(BuildInfo.sha == "unknown" || BuildInfo.sha.count == 7)
        if BuildInfo.sha == "unknown" {
            #expect(LocalWireBuild.line == "記録なし")
        }
    }
}
