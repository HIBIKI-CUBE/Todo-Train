//
//  StoreSchemaVersion.swift
//  Todo train
//
//  The version `AppModelContainer` opens. A later schema swap in that container
//  is the only edit required; this file does not name a schema generation.
//

import SwiftData

enum StoreSchemaVersion {
    static var current: Schema.Version { AppModelContainer.schema.version }

    static var wire: String {
        let version = current
        return "\(version.major).\(version.minor).\(version.patch)"
    }

    static var major: Int { current.major }
}
