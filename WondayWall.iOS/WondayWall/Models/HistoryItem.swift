import Foundation

// 生成ステータス
enum GenerationStatus: String, Codable {
    case success = "success"
    case failure = "failure"
    case skipped = "skipped"
}

// 生成履歴の1件
struct HistoryItem: Codable, Identifiable {
    var id: UUID
    let executedAt: Date
    let status: GenerationStatus
    // アプリ内に保存した画像のファイルパス
    let imagePath: String?
    // 使用したカレンダーイベント
    let usedCalendarEvents: [CalendarEventItem]?
    // 使用したニューストピック
    let usedNewsTopics: [NewsTopicItem]?
    // 使用したユーザープロンプト
    let usedPrompt: String?
    // エラー概要（失敗時のみ）
    let errorSummary: String?

    var isSuccess: Bool { status == .success }
    var isSkipped: Bool { status == .skipped }

    init(
        id: UUID = UUID(),
        executedAt: Date = Date(),
        status: GenerationStatus,
        imagePath: String? = nil,
        usedCalendarEvents: [CalendarEventItem]? = nil,
        usedNewsTopics: [NewsTopicItem]? = nil,
        usedPrompt: String? = nil,
        errorSummary: String? = nil
    ) {
        self.id = id
        self.executedAt = executedAt
        self.status = status
        self.imagePath = imagePath
        self.usedCalendarEvents = usedCalendarEvents
        self.usedNewsTopics = usedNewsTopics
        self.usedPrompt = usedPrompt
        self.errorSummary = errorSummary
    }
}
