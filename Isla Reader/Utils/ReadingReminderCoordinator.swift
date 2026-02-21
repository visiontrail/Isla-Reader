//
//  ReadingReminderCoordinator.swift
//  LanRead
//
//  Created by Assistant on 2026/2/10.
//

import Foundation

@MainActor
final class ReadingReminderCoordinator: ObservableObject {
    static let shared = ReadingReminderCoordinator()

    @Published private(set) var continueReadingRequestID = 0
    @Published private(set) var reminderTapRequestID = 0

    private init() {}

    func requestContinueReading(triggeredByReminder: Bool) {
        continueReadingRequestID += 1
        if triggeredByReminder {
            reminderTapRequestID += 1
        }
        DebugLogger.info(
            "[LiveActivityFlow] ReadingReminderCoordinator received continue reading request. " +
            "triggeredByReminder=\(triggeredByReminder), continueReadingRequestID=\(continueReadingRequestID), reminderTapRequestID=\(reminderTapRequestID)"
        )
    }
}
