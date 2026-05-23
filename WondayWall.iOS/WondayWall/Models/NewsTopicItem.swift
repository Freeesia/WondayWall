import Foundation

// ニューストピック
struct NewsTopicItem: Codable, Identifiable {
    var id: String
    let title: String
    let summary: String?
    let url: String?
    let publishedAt: Date
    let ogpImageUrl: String?
    let sourceRssUrl: String?

    init(
        id: String,
        title: String,
        summary: String? = nil,
        url: String? = nil,
        publishedAt: Date,
        ogpImageUrl: String? = nil,
        sourceRssUrl: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.url = url
        self.publishedAt = publishedAt
        self.ogpImageUrl = ogpImageUrl
        self.sourceRssUrl = sourceRssUrl
    }
}
