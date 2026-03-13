//
//  Item.swift
//  20260312v2clothingfrontend
//
//  Created by Luca Liautaud on 3/12/26.
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
