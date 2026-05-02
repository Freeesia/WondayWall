import Foundation

// カレンダーイベント
struct CalendarEventItem: Codable, Identifiable {
    var id: String
    let title: String
    let startTime: Date
    let endTime: Date?
    let location: String?
    let calendarDescription: String?
}
