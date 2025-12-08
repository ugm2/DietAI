//
//  Item.swift
//  DietAI
//
//  Created by Unai Garay Maestre on 8/12/25.
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
