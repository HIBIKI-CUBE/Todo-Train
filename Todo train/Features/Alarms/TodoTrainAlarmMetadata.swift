//
//  TodoTrainAlarmMetadata.swift
//  Todo train
//

import Foundation

#if canImport(AlarmKit)
import AlarmKit

struct TodoTrainAlarmMetadata: AlarmMetadata, Codable, Hashable, Sendable {
    var ticketTitle: String
}
#endif
