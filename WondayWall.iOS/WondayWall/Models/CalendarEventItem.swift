import Foundation

// カレンダーイベント（EventKit EKEvent から変換）
struct CalendarEventItem: Codable, Identifiable {
    var id: String
    var calendarId: String
    let title: String
    let startTime: Date
    let endTime: Date?
    let isAllDay: Bool
    let location: String?
    let notes: String?
}
