import Foundation

// スケジュールスロット計算のユーティリティ
enum ScheduleHelper {
    static let defaultRunsPerDay = 4
    static let supportedRunsPerDay = [1, 2, 3, 4, 6, 8, 12, 24]

    // 有効な値に丸める（最近傍の選択肢に正規化）
    static func normalizeRunsPerDay(_ value: Int) -> Int {
        supportedRunsPerDay.contains(value) ? value : defaultRunsPerDay
    }

    // 1スロットあたりの時間間隔
    static func slotInterval(runsPerDay: Int) -> TimeInterval {
        24.0 * 3600.0 / Double(normalizeRunsPerDay(runsPerDay))
    }

    // 指定日時以前の最新スケジュールスロット開始時刻を返す
    static func getLatestScheduledSlotAtOrBefore(_ date: Date, runsPerDay: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let interval = slotInterval(runsPerDay: normalizeRunsPerDay(runsPerDay))
        let secondsSinceStart = date.timeIntervalSince(startOfDay)
        let slotIndex = floor(secondsSinceStart / interval)
        return startOfDay.addingTimeInterval(slotIndex * interval)
    }

    // 指定日時の次のスケジュールスロット開始時刻を返す
    static func getNextScheduledSlotAfter(_ date: Date, runsPerDay: Int) -> Date {
        let latestSlot = getLatestScheduledSlotAtOrBefore(date, runsPerDay: runsPerDay)
        return latestSlot.addingTimeInterval(slotInterval(runsPerDay: runsPerDay))
    }

    // 未処理スロットがあるか判定する
    // 最新スロット以降に成功履歴がなければ true を返す
    static func isPendingGeneration(
        now: Date,
        lastSuccessAt: Date?,
        runsPerDay: Int
    ) -> Bool {
        let latestSlot = getLatestScheduledSlotAtOrBefore(now, runsPerDay: runsPerDay)
        guard let lastSuccess = lastSuccessAt else { return true }
        return lastSuccess < latestSlot
    }

    // 表示用の「N回/日」文字列を返す
    static func displayText(runsPerDay: Int) -> String {
        "\(normalizeRunsPerDay(runsPerDay))回/日"
    }
}
