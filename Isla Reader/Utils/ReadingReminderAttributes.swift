//
//  ReadingReminderAttributes.swift
//  LanRead
//
//  Created by Assistant on 2026/2/10.
//

import Foundation
import ActivityKit

struct ReadingReminderAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var goalMinutes: Int
        var minutesReadToday: Int
        var deepLink: String
    }

    var reminderDate: Date
}
