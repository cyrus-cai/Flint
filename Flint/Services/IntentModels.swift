//
//  IntentModels.swift
//  Flint
//
//  Created by AI Agent on 1/22/26.
//

import Foundation

// MARK: - Intent Types

/// The type of intent detected from user's natural language input
enum IntentType: String, Codable {
    case scheduleReminder    // 定时提醒
    case createCalendarEvent // 日历事件
    case textEditing         // 文本编辑
    case quickNote           // 普通笔记
    case unknown

    var displayName: String {
        switch self {
        case .scheduleReminder:
            return L("Schedule Reminder")
        case .createCalendarEvent:
            return L("Create Calendar Event")
        case .textEditing:
            return L("Text Editing")
        case .quickNote:
            return L("Quick Note")
        case .unknown:
            return L("Unknown")
        }
    }

    var iconName: String {
        switch self {
        case .scheduleReminder:
            return "bell.fill"
        case .createCalendarEvent:
            return "calendar"
        case .textEditing:
            return "pencil"
        case .quickNote:
            return "note.text"
        case .unknown:
            return "questionmark.circle"
        }
    }
}

// MARK: - Parsed DateTime

/// Represents a parsed date/time from natural language
struct ParsedDateTime: Codable {
    let date: Date
    let isAllDay: Bool
    let confidence: Double
    let originalText: String

    /// Human-readable formatted date string
    var formattedDate: String {
        let formatter = DateFormatter()
        if isAllDay {
            formatter.dateStyle = .full
            formatter.timeStyle = .none
        } else {
            formatter.dateStyle = .full
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    /// Short formatted date string
    var shortFormattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter.string(from: date)
    }

    /// Relative time description (e.g., "明天", "下周一")
    var relativeDescription: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return L("Today") + " " + formatter.string(from: date)
        } else if calendar.isDateInTomorrow(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return L("Tomorrow") + " " + formatter.string(from: date)
        } else {
            return formattedDate
        }
    }
}

// MARK: - Intent Response

/// The response from AI intent analysis
struct IntentResponse: Codable {
    let intent: IntentType
    let title: String?
    let parsedDateTime: ParsedDateTime?
    let notes: String?
    let confidence: Double
    let rawInterpretation: String

    /// Whether the intent has high enough confidence to proceed
    var isHighConfidence: Bool {
        return confidence >= 0.7
    }

    /// Whether time information is available
    var hasTimeInfo: Bool {
        return parsedDateTime != nil
    }

    /// Get a user-friendly summary of the intent
    var summary: String {
        switch intent {
        case .scheduleReminder:
            if let title = title, let dateTime = parsedDateTime {
                return String(format: L("Remind you to \"%@\" at %@"), title, dateTime.relativeDescription)
            }
            return rawInterpretation
        case .createCalendarEvent:
            if let title = title, let dateTime = parsedDateTime {
                return String(format: L("Create event \"%@\" at %@"), title, dateTime.relativeDescription)
            }
            return rawInterpretation
        default:
            return rawInterpretation
        }
    }
}

// MARK: - AI Agent State

/// State of the AI agent processing
enum AIAgentState {
    case idle
    case analyzing
    case confirming(IntentResponse)
    case executing
    case completed(success: Bool, message: String)
    case failed(String)

    var isProcessing: Bool {
        switch self {
        case .analyzing, .executing:
            return true
        default:
            return false
        }
    }

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isCompleted: Bool {
        if case .completed = self { return true }
        return false
    }
}

// MARK: - Reminder Result

/// Result of creating a reminder
struct ReminderResult {
    let success: Bool
    let reminderId: String?
    let errorMessage: String?

    static func success(id: String) -> ReminderResult {
        return ReminderResult(success: true, reminderId: id, errorMessage: nil)
    }

    static func failure(message: String) -> ReminderResult {
        return ReminderResult(success: false, reminderId: nil, errorMessage: message)
    }
}

// MARK: - Calendar Event Result

/// Result of creating a calendar event
struct CalendarEventResult {
    let success: Bool
    let eventId: String?
    let errorMessage: String?

    static func success(id: String) -> CalendarEventResult {
        return CalendarEventResult(success: true, eventId: id, errorMessage: nil)
    }

    static func failure(message: String) -> CalendarEventResult {
        return CalendarEventResult(success: false, eventId: nil, errorMessage: message)
    }
}
