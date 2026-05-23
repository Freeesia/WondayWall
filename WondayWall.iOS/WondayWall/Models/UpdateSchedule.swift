import Foundation

// 自動更新スケジュール（Windows版の UpdateSchedule 列挙型に対応）
enum UpdateSchedule: String, Codable, CaseIterable {
    case onceAWeek        // 週1回（月曜 4:00）
    case twiceAWeek       // 週2回（月曜・木曜 4:00）
    case threeTimesAWeek  // 週3回（月曜・水曜・金曜 4:00）
    case onceADay         // 1日1回（4:00）
    case threeTimesADay   // 1日3回（4:00 / 12:00 / 18:00）
}
