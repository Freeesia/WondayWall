import Foundation

// スケジュールスロット計算のユーティリティ（Windows版の ScheduleHelper に対応）
enum ScheduleHelper {
    // すべてのスケジュールで1日の最初の更新は4:00に揃える
    private static let firstDailySlotHour = 4

    static let defaultSchedule: UpdateSchedule = .onceADay
    static let supportedSchedules: [UpdateSchedule] = UpdateSchedule.allCases

    // 週次スケジュールかどうか
    static func isWeeklySchedule(_ schedule: UpdateSchedule) -> Bool {
        schedule == .onceAWeek || schedule == .twiceAWeek || schedule == .threeTimesAWeek
    }

    // 週次スケジュールの対象曜日（Gregorian calendar の weekday: 日曜=1, 月曜=2, ...）
    static func weekdays(for schedule: UpdateSchedule) -> [Int] {
        switch schedule {
        case .onceAWeek: return [2]         // 月曜
        case .twiceAWeek: return [2, 5]     // 月・木
        case .threeTimesAWeek: return [2, 4, 6]  // 月・水・金
        default: return []
        }
    }

    // 1日内のスロット時刻（時間単位）
    static func slotHours(for schedule: UpdateSchedule) -> [Int] {
        switch schedule {
        case .threeTimesADay: return [firstDailySlotHour, 12, 18]
        default: return [firstDailySlotHour]
        }
    }

    // 指定日時以前の最新スケジュールスロット開始時刻を返す
    static func getLatestScheduledSlotAtOrBefore(_ date: Date, schedule: UpdateSchedule) -> Date {
        let calendar = Calendar.current

        if isWeeklySchedule(schedule) {
            let days = weekdays(for: schedule)
            // 過去7日間を逆順に走査して直近の対象日を探す
            for i in 0..<7 {
                guard let dayStart = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: date)) else { continue }
                var comps = calendar.dateComponents([.year, .month, .day, .weekday], from: dayStart)
                comps.hour = firstDailySlotHour
                comps.minute = 0
                comps.second = 0
                guard let candidate = calendar.date(from: comps) else { continue }
                if candidate <= date, let weekday = comps.weekday, days.contains(weekday) {
                    return candidate
                }
            }
            // フォールバック（通常は到達しない）
            let fallback = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: date))
                ?? date.addingTimeInterval(-7 * 24 * 3600)
            return fallback.addingTimeInterval(Double(firstDailySlotHour) * 3600)
        } else {
            let hours = slotHours(for: schedule)
            let startOfDay = calendar.startOfDay(for: date)
            for hour in hours.reversed() {
                let candidate = startOfDay.addingTimeInterval(Double(hour) * 3600)
                if candidate <= date {
                    return candidate
                }
            }
            // 前日の最後のスロット
            let prevDay = calendar.date(byAdding: .day, value: -1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(-24 * 3600)
            return prevDay.addingTimeInterval(Double(hours.last ?? firstDailySlotHour) * 3600)
        }
    }

    // 指定日時の次のスケジュールスロット開始時刻を返す
    static func getNextScheduledSlotAfter(_ date: Date, schedule: UpdateSchedule) -> Date {
        let calendar = Calendar.current

        if isWeeklySchedule(schedule) {
            let days = weekdays(for: schedule)
            // 翌日から8日間走査して直近の対象曜日を探す
            for i in 1...8 {
                guard let dayStart = calendar.date(byAdding: .day, value: i, to: calendar.startOfDay(for: date)) else { continue }
                var comps = calendar.dateComponents([.year, .month, .day, .weekday], from: dayStart)
                comps.hour = firstDailySlotHour
                comps.minute = 0
                comps.second = 0
                guard let candidate = calendar.date(from: comps) else { continue }
                if let weekday = comps.weekday, days.contains(weekday) {
                    return candidate
                }
            }
            // フォールバック（通常は到達しない）
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date.addingTimeInterval(7 * 24 * 3600)
        } else {
            let hours = slotHours(for: schedule)
            let startOfDay = calendar.startOfDay(for: date)
            for hour in hours {
                let candidate = startOfDay.addingTimeInterval(Double(hour) * 3600)
                if candidate > date {
                    return candidate
                }
            }
            // 翌日の最初のスロット
            let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
                ?? startOfDay.addingTimeInterval(24 * 3600)
            return nextDay.addingTimeInterval(Double(hours.first ?? firstDailySlotHour) * 3600)
        }
    }

    // 未処理スロットがあるか判定する
    // 最新スロット以降に成功履歴がなければ true を返す
    static func isPendingGeneration(now: Date, lastSuccessAt: Date?, schedule: UpdateSchedule) -> Bool {
        let latestSlot = getLatestScheduledSlotAtOrBefore(now, schedule: schedule)
        guard let lastSuccess = lastSuccessAt else { return true }
        return lastSuccess < latestSlot
    }

    // 表示用文字列を返す
    static func displayText(for schedule: UpdateSchedule) -> String {
        switch schedule {
        case .onceAWeek: return "週1回（月曜）"
        case .twiceAWeek: return "週2回（月曜・木曜）"
        case .threeTimesAWeek: return "週3回（月曜・水曜・金曜）"
        case .onceADay: return "1日1回"
        case .threeTimesADay: return "1日3回（朝・昼・晩）"
        }
    }

    // 旧バージョンの runsPerDay 値から UpdateSchedule へマイグレーションする
    // 1, 2 は OnceADay、3 以上は ThreeTimesADay にマップする
    static func migrateFromRunsPerDay(_ runsPerDay: Int) -> UpdateSchedule {
        runsPerDay <= 2 ? .onceADay : .threeTimesADay
    }
}

