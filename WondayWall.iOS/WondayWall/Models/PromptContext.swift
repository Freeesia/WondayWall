import Foundation

// 画像生成プロンプト用カレンダーイベント
struct PromptCalendarEvent: Codable {
    let id: String
    let title: String
    // "today", "tomorrow", "in N days" などの近接タグ
    let proximityTag: String
    let startTime: Date
    let endTime: Date?
    let location: String?
    let description: String?
}

// 画像生成プロンプト用ニューストピック
struct PromptNewsTopic: Codable {
    let id: String
    let title: String
    let summary: String?
    let url: String?
    let publishedAt: Date?
    let ogpImageUrl: String?
}

// 画像生成に渡すコンテキスト一式
struct PromptContext: Codable {
    var calendarEvents: [PromptCalendarEvent] = []
    var newsTopics: [PromptNewsTopic] = []
    // iPhone 15 Pro Max ポートレート解像度
    var imageSize: String = "1290x2796"
    var aspectRatio: String = "9:19.5"
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
