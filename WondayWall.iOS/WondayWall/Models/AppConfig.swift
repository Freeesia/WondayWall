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
    // 手動生成でも Flex ティアを強制使用する
    var forceFlexTier: Bool = false
    // WondayWall アルバムの最大保存枚数（超過分は古い順にアルバムから外す）
    var albumMaxCount: Int = 1
    // 初回セットアップ完了済みかどうか
    var hasCompletedInitialSetup: Bool = false
    // 初回セットアップ時に保存した画面のネイティブピクセルサイズ
    var screenNativePixelWidth: Double?
    var screenNativePixelHeight: Double?
}
