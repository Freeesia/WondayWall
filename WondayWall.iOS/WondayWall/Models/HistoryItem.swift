import Foundation

// 生成ステータス（定義順は処理の昇順）
enum GenerationStatus: String, Codable {
    case generating               = "generating"                    // 開始・プロンプト生成前（後方互換）
    case generatingPromptReady    = "generating_prompt_ready"       // プロンプト生成後・画像 API 前
    case generatingImageRequested = "generating_image_requested"    // 画像 API 呼び出し済み（再開不可）
    case success                  = "success"                       // 生成成功
    case skipped                  = "skipped"                       // スキップ（変化なし）
    case failure                  = "failure"                       // 生成失敗
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
    // テキストモデルが生成した画像プロンプト（generatingPromptReady 以降で設定、再開用）
    let generatedPrompt: String?

    var isSuccess: Bool { status == .success }
    var isSkipped: Bool { status == .skipped }
    var isGenerating: Bool {
        switch status {
        case .generating, .generatingPromptReady, .generatingImageRequested: return true
        default: return false
        }
    }

    init(
        id: UUID = UUID(),
        executedAt: Date = Date(),
        status: GenerationStatus,
        usedCalendarEvents: [CalendarEventItem]? = nil,
        usedNewsTopics: [NewsTopicItem]? = nil,
        usedPrompt: String? = nil,
        errorSummary: String? = nil,
        photoAssetId: String? = nil,
        generatedPrompt: String? = nil
    ) {
        self.id = id
        self.executedAt = executedAt
        self.status = status
        self.usedCalendarEvents = usedCalendarEvents
        self.usedNewsTopics = usedNewsTopics
        self.usedPrompt = usedPrompt
        self.errorSummary = errorSummary
        self.photoAssetId = photoAssetId
        self.generatedPrompt = generatedPrompt
    }
}
