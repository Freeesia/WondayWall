import Foundation

// 標準カレンダーのソース（Google / iCloud / Exchange / CalDAV など）とカレンダー情報
struct CalendarSourceItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let sourceTitle: String
    let sourceType: String
    let colorHex: String?
}
