import Foundation

// アプリ設定モデル
struct AppConfig: Codable {
    // 取得対象のカレンダー識別子一覧（EKCalendar.calendarIdentifier）
    var targetCalendarIds: [String] = []
    // RSS ソース URL 一覧
    var rssSources: [String] = []
    // ユーザー追加プロンプト
    var userPrompt: String = ""
    // 1日あたりの自動生成回数
    var runsPerDay: Int = 1
    // 自動生成有効/無効
    var autoGenerationEnabled: Bool = true
    // 変化がなければ生成をスキップする
    var skipIfNoChanges: Bool = false
    // 通知を有効にする
    var notificationsEnabled: Bool = true
    // Wi-Fi 接続時のみ生成する
    var wifiOnlyGeneration: Bool = false
}
