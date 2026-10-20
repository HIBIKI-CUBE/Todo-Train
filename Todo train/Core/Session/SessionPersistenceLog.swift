//
//  SessionPersistenceLog.swift
//  Todo train
//

import OSLog

enum SessionPersistenceLog {
    private static let logger = Logger(subsystem: "dev.hibiki-cube.Todo-train", category: "SessionPersistence")

    static func saveFailed(operation: StaticString, error: Error) {
        logger.error(
            "save failed in \(operation, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }
}
