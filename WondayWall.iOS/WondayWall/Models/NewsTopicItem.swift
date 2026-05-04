import Foundation

// ニューストピック
struct NewsTopicItem: Codable, Identifiable {
    var id: String
    let title: String
    let summary: String?
    let url: String?
    let publishedAt: Date
    let ogpImageUrl: String?
}
