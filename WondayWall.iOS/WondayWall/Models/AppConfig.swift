import Foundation

// アプリ設定モデル
struct AppConfig: Codable {
    // 取得対象のカレンダー識別子一覧（EKCalendar.calendarIdentifier）
    var targetCalendarIds: [String] = []
    // RSS ソース URL 一覧
    var rssSources: [String] = []
    // ユーザー追加プロンプト
    var userPrompt: String = ""
    // 自動更新スケジュール
    var schedule: UpdateSchedule = .onceADay
    // 自動生成有効/無効
    var autoGenerationEnabled: Bool = true
    // 変化がなければ生成をスキップする
    var skipIfNoChanges: Bool = false
    // 通知を有効にする
    var notificationsEnabled: Bool = true
    // Wi-Fi 接続時のみ生成する
    var wifiOnlyGeneration: Bool = false

    init() {}

    // マイグレーション用に旧フィールドを含む CodingKeys
    private enum CodingKeys: String, CodingKey {
        case targetCalendarIds, rssSources, userPrompt, schedule
        case autoGenerationEnabled, skipIfNoChanges, notificationsEnabled, wifiOnlyGeneration
        case runsPerDay  // 旧フィールド（マイグレーション用）
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetCalendarIds = (try? container.decode([String].self, forKey: .targetCalendarIds)) ?? []
        rssSources = (try? container.decode([String].self, forKey: .rssSources)) ?? []
        userPrompt = (try? container.decode(String.self, forKey: .userPrompt)) ?? ""
        autoGenerationEnabled = (try? container.decode(Bool.self, forKey: .autoGenerationEnabled)) ?? true
        skipIfNoChanges = (try? container.decode(Bool.self, forKey: .skipIfNoChanges)) ?? false
        notificationsEnabled = (try? container.decode(Bool.self, forKey: .notificationsEnabled)) ?? true
        wifiOnlyGeneration = (try? container.decode(Bool.self, forKey: .wifiOnlyGeneration)) ?? false

        // 新フィールドを優先し、なければ旧 runsPerDay からマイグレーションする
        if let s = try? container.decode(UpdateSchedule.self, forKey: .schedule) {
            schedule = s
        } else if let rpd = try? container.decode(Int.self, forKey: .runsPerDay) {
            schedule = ScheduleHelper.migrateFromRunsPerDay(rpd)
        } else {
            schedule = .onceADay
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetCalendarIds, forKey: .targetCalendarIds)
        try container.encode(rssSources, forKey: .rssSources)
        try container.encode(userPrompt, forKey: .userPrompt)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(autoGenerationEnabled, forKey: .autoGenerationEnabled)
        try container.encode(skipIfNoChanges, forKey: .skipIfNoChanges)
        try container.encode(notificationsEnabled, forKey: .notificationsEnabled)
        try container.encode(wifiOnlyGeneration, forKey: .wifiOnlyGeneration)
        // runsPerDay はエンコードしない（新フィールドを使用）
    }
}

