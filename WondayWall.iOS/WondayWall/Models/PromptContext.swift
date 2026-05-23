import Foundation

// 画像生成プロンプト用カレンダーイベント
struct PromptCalendarEvent: Encodable {
    let id: String
    let title: String
    // "today", "tomorrow", "in N days" などの近接タグ
    let proximityTag: String
    let startTime: Date
    let endTime: Date?
    let location: String?
    let description: String?
}

// 画像生成プロンプト用ニューストピック（ランタイム専用、JSON 保存なし）
struct PromptNewsTopic: Encodable {
    let id: String
    let title: String
    let summary: String?
    let url: String?
    let publishedAt: Date?
    let ogpImageUrl: String?
    // OGP 画像データ（ランタイム専用。Gemini API の JSON には含めない）
    var ogpImageData: Data? = nil
    var ogpImageMimeType: String? = nil

    // ogpImageData / ogpImageMimeType を Encodable から除外する
    enum CodingKeys: String, CodingKey {
        case id, title, summary, url, publishedAt, ogpImageUrl
    }
}

// 画像生成に渡すコンテキスト一式（ランタイム専用、JSON 保存なし）
struct PromptContext {
    var calendarEvents: [PromptCalendarEvent] = []
    var newsTopics: [PromptNewsTopic] = []
    // Gemini API で利用可能な縦長比率（imageSize は "512" / "1K" / "2K" / "4K" 形式）
    var imageSize: String = "2K"
    var aspectRatio: String = "9:16"
    var additionalConstraints: String = ""
    // ベース壁紙のファイルパス（前回生成画像を参照する場合）
    var baseImagePath: String?
}

// コンテキスト構築の結果
struct ContextBuildResult {
    let promptContext: PromptContext
    let calendarEvents: [CalendarEventItem]
    let newsTopics: [NewsTopicItem]
}
