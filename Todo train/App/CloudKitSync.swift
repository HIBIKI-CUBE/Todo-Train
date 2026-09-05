//
//  CloudKitSync.swift
//  Todo train
//
//  SwiftData の CloudKit 私有同期。実同期には有料 Apple Developer Program と
//  iCloud / CloudKit Capability が必要。Personal Team に entitlement を足すと
//  署名が失敗するので、既定はローカル store（`.none`）。
//

import Foundation
import SwiftData
import UIKit

enum CloudKitSync {
    static let containerIdentifier = "iCloud.dev.hibiki-cube.Todo-train"

    #if DEBUG
    /// Tests only. Production always reads as `false` until a paid team flips the source.
    static var isConfiguredOverride: Bool?
    #endif

    /// Flip the source `false` → `true` only after a paid Apple Developer Program team
    /// has the iCloud CloudKit container in the App ID. Personal Team + iCloud entitlement
    /// fails signing.
    static var isConfigured: Bool {
        #if DEBUG
        if let isConfiguredOverride { return isConfiguredOverride }
        #endif
        return false
    }

    static func configuration(schema: Schema, inMemory: Bool) -> ModelConfiguration {
        if inMemory {
            return ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
        if isConfigured {
            return ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(containerIdentifier)
            )
        }
        return ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .none
        )
    }
}

protocol DeviceIdentifying: Sendable {
    var id: String { get }
}

struct SystemDeviceIdentity: DeviceIdentifying {
    var id: String { LocalDeviceID.current }
}

struct FixedDeviceIdentity: DeviceIdentifying {
    var id: String
}

enum LocalDeviceID {
    static var current: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown-device"
    }
}
