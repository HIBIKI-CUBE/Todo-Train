//
//  Item.swift
//  Todo train
//
//  Created by HIBIKI CUBE on 2026/08/11.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
