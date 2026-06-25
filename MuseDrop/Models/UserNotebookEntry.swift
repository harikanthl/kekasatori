//
//  UserNotebookEntry.swift
//  MuseDrop
//

import Foundation

struct UserNotebookEntry: Identifiable, Hashable, Sendable {
    let id: UUID
    let downloadId: UUID
    let dayKey: String
    var content: String
    var richContent: Data?
    var formatting: NotebookPageFormatting
    var template: NotebookPageTemplate
    let createdAt: Date
    var updatedAt: Date
    
    var isToday: Bool {
        dayKey == NotebookDayKey.today()
    }
}

enum NotebookDayKey {
    private static let storageFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = .current
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
    
    static func from(_ date: Date) -> String {
        storageFormatter.string(from: date)
    }
    
    static func today() -> String {
        from(Date())
    }
    
    static func date(from dayKey: String) -> Date? {
        storageFormatter.date(from: dayKey)
    }
    
    static func displayTitle(for dayKey: String) -> String {
        if dayKey == today() {
            return "Today"
        }
        guard let date = date(from: dayKey) else { return dayKey }
        return displayFormatter.string(from: date)
    }
    
    static func displaySubtitle(for dayKey: String) -> String {
        guard let date = date(from: dayKey) else { return dayKey }
        if dayKey == today() {
            return displayFormatter.string(from: date)
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = .current
        formatter.timeZone = Calendar.current.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }
}
