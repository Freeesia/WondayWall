import Foundation
import FeedKit
import GoogleSignIn
import SwiftSoup

// Google Calendar への接続と RSS フィードからコンテキストを構築するサービス
final class ContextService {
    // Google Calendar 読み取りスコープ
    private static let calendarScope = "https://www.googleapis.com/auth/calendar.readonly"

    private let configService: AppConfigService
    private let historyService: HistoryService

    init(configService: AppConfigService, historyService: HistoryService) {
        self.configService = configService
        self.historyService = historyService
    }

    // サイレントにカレンダーへアクセス可能かを確認する
    func canAccessCalendarSilently() async -> Bool {
        if GIDSignIn.sharedInstance.currentUser != nil { return true }
        do {
            try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return GIDSignIn.sharedInstance.currentUser != nil
        } catch {
            return false
        }
    }

    // Google Sign-In でブラウザ認証を行い、Calendar スコープを取得する
    @MainActor
    func authorizeCalendarInteractive(presentingViewController: UIViewController) async throws {
        _ = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: presentingViewController,
            hint: nil,
            additionalScopes: [Self.calendarScope]
        )
    }

    // Google Calendar 認証情報を削除する
    func disconnectCalendar() {
        GIDSignIn.sharedInstance.signOut()
    }

    // 利用可能なカレンダー一覧を取得する
    func fetchAvailableCalendars() async throws -> [AvailableCalendar] {
        let accessToken = try await getValidAccessToken()
        var request = URLRequest(
            url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!
        )
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return response.items.map {
            AvailableCalendar(
                id: $0.id,
                summary: $0.summary ?? $0.id,
                isPrimary: $0.primary ?? false
            )
        }
    }

    // 直近 7 日間のカレンダーイベントを取得する
    func fetchCalendarEvents() async throws -> [CalendarEventItem] {
        let accessToken = try await getValidAccessToken()
        let now = Date()
        let end = now.addingTimeInterval(7 * 24 * 3600)
        let formatter = ISO8601DateFormatter()

        var results: [CalendarEventItem] = []
        for calId in configService.config.targetCalendarIds {
            let encodedId =
                calId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calId
            var components = URLComponents(
                string:
                    "https://www.googleapis.com/calendar/v3/calendars/\(encodedId)/events"
            )!
            components.queryItems = [
                URLQueryItem(name: "timeMin", value: formatter.string(from: now)),
                URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
                URLQueryItem(name: "singleEvents", value: "true"),
                URLQueryItem(name: "orderBy", value: "startTime"),
                URLQueryItem(name: "maxResults", value: "10"),
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            guard let (data, _) = try? await URLSession.shared.data(for: request),
                let response = try? JSONDecoder().decode(CalendarEventsResponse.self, from: data)
            else {
                continue
            }
            for event in response.items {
                let startTime = parseCalendarDateTime(event.start)
                let endTime: Date? = event.end.map { parseCalendarDateTime($0) }
                results.append(
                    CalendarEventItem(
                        id: event.id,
                        title: event.summary ?? "(タイトルなし)",
                        startTime: startTime,
                        endTime: endTime,
                        location: event.location,
                        calendarDescription: event.description
                    )
                )
            }
        }
        return results
    }

    // RSS/Atom フィードからニュースを取得し、OGP 画像 URL を付与する
    func fetchNews() async -> [NewsTopicItem] {
        let rssSources = configService.config.rssSources
        guard !rssSources.isEmpty else { return [] }
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)

        // RSS フィードから記事を並列取得
        let rssItems = await withTaskGroup(of: [RssItem].self) { group in
            for url in rssSources {
                group.addTask { await self.fetchRssItems(from: url, since: weekAgo) }
            }
            var all: [RssItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }

        // 日付でソートして一意化
        let sortedItems = rssItems.sorted { $0.publishedAt > $1.publishedAt }

        // 上位 10 件について OGP 画像 URL を並列取得する（それ以降は nil）
        let ogpURLs = await withTaskGroup(of: (String, String?).self) { group in
            for item in sortedItems.prefix(10) {
                if let url = item.url {
                    group.addTask { (url, await self.fetchOGPImageURL(from: url)) }
                }
            }
            var map: [String: String] = [:]
            for await (key, ogp) in group {
                if let ogp { map[key] = ogp }
            }
            return map
        }

        return sortedItems.map { item in
            let ogp = item.url.flatMap { ogpURLs[$0] }
            return NewsTopicItem(
                id: item.url ?? item.title,
                title: item.title,
                summary: item.summary,
                url: item.url,
                publishedAt: item.publishedAt,
                ogpImageUrl: ogp
            )
        }
    }

    // 1つの RSS ソースからアイテムを取得してパースする（FeedKit使用）
    private func fetchRssItems(from urlString: String, since: Date) async -> [RssItem] {
        guard let url = URL(string: urlString) else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }

        let feedResult: Result<Feed, ParserError> = await withCheckedContinuation { continuation in
            FeedParser(data: data).parseAsync { continuation.resume(returning: $0) }
        }

        guard case .success(let feed) = feedResult else { return [] }

        let items: [RssItem]
        switch feed {
        case .atom(let atomFeed):
            items = (atomFeed.entries ?? []).compactMap { entry in
                guard let title = entry.title else { return nil }
                let link = entry.links?
                    .first(where: { $0.attributes?.rel == "alternate" })?
                    .attributes?.href
                    ?? entry.links?.first?.attributes?.href
                return RssItem(
                    title: title,
                    summary: entry.summary?.value,
                    url: link,
                    publishedAt: entry.published ?? entry.updated ?? Date()
                )
            }
        case .rss(let rssFeed):
            items = (rssFeed.items ?? []).compactMap { item in
                guard let title = item.title else { return nil }
                return RssItem(
                    title: title,
                    summary: item.description,
                    url: item.link,
                    publishedAt: item.pubDate ?? Date()
                )
            }
        case .json(let jsonFeed):
            items = (jsonFeed.items ?? []).compactMap { item in
                guard let title = item.title else { return nil }
                return RssItem(
                    title: title,
                    summary: item.summary,
                    url: item.url,
                    publishedAt: item.datePublished ?? Date()
                )
            }
        }

        return items.filter { $0.publishedAt >= since }
    }

    // SwiftSoup で記事 HTML から OGP 画像 URL を抽出する
    private func fetchOGPImageURL(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        guard let html = String(data: data, encoding: .utf8) else { return nil }
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let selectors = [
            "meta[property='og:image']",
            "meta[property='og:image:url']",
            "meta[name='twitter:image']",
            "meta[name='twitter:image:src']",
        ]
        for selector in selectors {
            if let content = try? doc.select(selector).first()?.attr("content"),
               !content.isEmpty
            {
                return content
            }
        }
        return nil
    }

    // 画像生成用コンテキストを構築する
    func buildContext() async -> ContextBuildResult {
        let config = configService.config
        let cal = Calendar.current

        // カレンダーイベントを最大5件取得
        let allEvents = (try? await fetchCalendarEvents()) ?? []
        let events = Array(allEvents.prefix(5))

        // ニューストピックを取得して選別する
        let recentNews = await fetchNews()
        let lastGenerated = historyService.getLastSuccessfulGenerated()
        let news = selectPromptNewsItems(
            recentNews: recentNews,
            lastGeneratedAt: lastGenerated?.executedAt
        )

        let promptContext = PromptContext(
            calendarEvents: events.enumerated().map { index, e in
                let days = cal.dateComponents([.day], from: Date(), to: e.startTime).day ?? 0
                let proximityTag: String
                switch days {
                case ...0: proximityTag = "today"
                case 1: proximityTag = "tomorrow"
                default: proximityTag = "in \(days) days"
                }
                return PromptCalendarEvent(
                    id: "event-\(index + 1)",
                    title: e.title,
                    proximityTag: proximityTag,
                    startTime: e.startTime,
                    endTime: e.endTime,
                    location: e.location,
                    description: e.calendarDescription
                )
            },
            newsTopics: news.enumerated().map { index, n in
                PromptNewsTopic(
                    id: "news-\(index + 1)",
                    title: n.title,
                    summary: n.summary,
                    url: n.url,
                    publishedAt: n.publishedAt,
                    ogpImageUrl: n.ogpImageUrl
                )
            },
            imageSize: "1290x2796",
            aspectRatio: "9:19.5",
            additionalConstraints: config.userPrompt
        )

        return ContextBuildResult(
            promptContext: promptContext,
            calendarEvents: events,
            newsTopics: news
        )
    }

    // プロンプト用ニュースを選別する（最大10件）
    private func selectPromptNewsItems(
        recentNews: [NewsTopicItem],
        lastGeneratedAt: Date?
    ) -> [NewsTopicItem] {
        let maxCount = 10
        let maxRecentSinceLastGeneration = 3
        var selected: [NewsTopicItem] = []
        var selectedKeys = Set<String>()

        @discardableResult
        func tryAdd(_ item: NewsTopicItem) -> Bool {
            let key = item.url ?? item.title
            guard selected.count < maxCount, selectedKeys.insert(key).inserted else {
                return false
            }
            selected.append(item)
            return true
        }

        // 直前の生成以降の新着を優先的に含める
        if let lastGenerated = lastGeneratedAt {
            var recentSince = recentNews.filter { $0.publishedAt > lastGenerated }
            if recentSince.count > maxRecentSinceLastGeneration {
                recentSince = Array(recentSince.shuffled().prefix(maxRecentSinceLastGeneration))
                recentSince.sort { $0.publishedAt > $1.publishedAt }
            }
            recentSince.forEach { tryAdd($0) }
        }

        // 各ソースの先頭アイテムと残りを追加
        recentNews.forEach { tryAdd($0) }

        return selected.sorted { $0.publishedAt > $1.publishedAt }
    }

    // 有効なアクセストークンを返す（GIDSignIn が自動リフレッシュ）
    private func getValidAccessToken() async throws -> String {
        if let user = GIDSignIn.sharedInstance.currentUser {
            try await user.refreshTokensIfNeeded()
            return user.accessToken.tokenString
        }
        // サイレント復元を試みる
        try await GIDSignIn.sharedInstance.restorePreviousSignIn()
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            throw NSError(
                domain: "WondayWall",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Googleカレンダーが未接続です。設定から接続してください。"
                ]
            )
        }
        try await user.refreshTokensIfNeeded()
        return user.accessToken.tokenString
    }

    // カレンダー API の日時フィールドを Date に変換する
    private func parseCalendarDateTime(_ dt: CalendarDateTime) -> Date {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let dateTimeStr = dt.dateTime, let date = isoFormatter.date(from: dateTimeStr) {
            return date
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let dateTimeStr = dt.dateTime, let date = isoFormatter.date(from: dateTimeStr) {
            return date
        }
        // 終日イベントは "yyyy-MM-dd" 形式
        if let dateStr = dt.date {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.locale = Locale(identifier: "en_US_POSIX")
            return df.date(from: dateStr) ?? Date()
        }
        return Date()
    }

    // MARK: - 内部モデル（Google Calendar REST API レスポンス）

    private struct CalendarListResponse: Codable {
        let items: [CalendarListEntry]
    }

    private struct CalendarListEntry: Codable {
        let id: String
        let summary: String?
        let primary: Bool?
    }

    private struct CalendarEventsResponse: Codable {
        let items: [CalendarEvent]
    }

    private struct CalendarEvent: Codable {
        let id: String
        let summary: String?
        let start: CalendarDateTime
        let end: CalendarDateTime?
        let location: String?
        let description: String?
    }

    private struct CalendarDateTime: Codable {
        let dateTime: String?
        let date: String?
    }

    // RSS フィードアイテム（内部用）
    private struct RssItem {
        let title: String
        let summary: String?
        let url: String?
        let publishedAt: Date
    }
}

// 利用可能なカレンダー
struct AvailableCalendar: Identifiable {
    let id: String
    let summary: String
    let isPrimary: Bool
}
