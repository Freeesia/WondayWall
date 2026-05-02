import Foundation

// アプリ設定モデル
struct AppConfig: Codable {
    // Google AI API キー
    var googleAiApiKey: String = ""
    // 取得対象の Google カレンダー ID 一覧
    var targetCalendarIds: [String] = []
    // RSS ソース URL 一覧
    var rssSources: [String] = []
    // ユーザー追加プロンプト
    var userPrompt: String = ""
    // 1日あたりの自動生成回数
    var runsPerDay: Int = 1
    // 自動生成有効/無効
    var autoGenerationEnabled: Bool = false
    // 変化がなければ生成をスキップする
    var skipIfNoChanges: Bool = false
    // 生成画像を写真ライブラリに自動保存する
    var saveToPhotosEnabled: Bool = false
    // 通知を有効にする
    var notificationsEnabled: Bool = false
    // Wi-Fi 接続時のみ生成する
    var wifiOnlyGeneration: Bool = false
    // 低電力モード時は生成しない
    var skipOnLowPowerMode: Bool = false
}
