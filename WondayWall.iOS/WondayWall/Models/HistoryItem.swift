import Foundation

// 生成ステータス
enum GenerationStatus: String, Codable {
    case success = "success"
    case failure = "failure"
    case skipped = "skipped"
    case generating = "generating"
}

// 生成履歴の1件
struct HistoryItem: Codable, Identifiable {
    var id: UUID
    let executedAt: Date
    let status: GenerationStatus
    // 使用したカレンダーイベント
    let usedCalendarEvents: [CalendarEventItem]?
    // 使用したニューストピック
    let usedNewsTopics: [NewsTopicItem]?
    // 使用したユーザープロンプト
    let usedPrompt: String?
    // エラー概要（失敗時のみ）
    let errorSummary: String?
    // 写真ライブラリに保存したアセット識別子（アルバム管理用）
    let photoAssetId: String?

    var isSuccess: Bool { status == .success }
    var isSkipped: Bool { status == .skipped }
    var isGenerating: Bool { status == .generating }

    init(
        id: UUID = UUID(),
        executedAt: Date = Date(),
        status: GenerationStatus,
        usedCalendarEvents: [CalendarEventItem]? = nil,
        usedNewsTopics: [NewsTopicItem]? = nil,
        usedPrompt: String? = nil,
        errorSummary: String? = nil,
        photoAssetId: String? = nil
    ) {
        self.id = id
        self.executedAt = executedAt
        self.status = status
        self.usedCalendarEvents = usedCalendarEvents
        self.usedNewsTopics = usedNewsTopics
        self.usedPrompt = usedPrompt
        self.errorSummary = errorSummary
        self.photoAssetId = photoAssetId
    }
}
