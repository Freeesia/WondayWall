import Foundation
import EventKit
import FeedKit
import SwiftSoup

// RSS フィードからコンテキストを構築し、EventKit 経由でカレンダーイベントを取得するサービス
final class ContextService {
    private let configService: AppConfigService
    private let historyService: HistoryService
    private let calendarService: EventKitCalendarService

    init(
        configService: AppConfigService,
        historyService: HistoryService,
        calendarService: EventKitCalendarService
    ) {
        self.configService = configService
        self.historyService = historyService
        self.calendarService = calendarService
    }

    // カレンダーへアクセス許可済みかを確認する
    func canAccessCalendarSilently() -> Bool {
        let status = calendarService.authorizationStatus()
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    // 端末に登録されているカレンダー一覧を返す
    func fetchAvailableCalendars() -> [CalendarSourceItem] {
        calendarService.fetchCalendars().map { cal in
            CalendarSourceItem(
                id: cal.calendarIdentifier,
                title: cal.title,
                sourceTitle: cal.source.title,
                sourceType: sourceTypeDescription(cal.source.sourceType),
                colorHex: colorHex(cal.cgColor)
            )
        }
    }

    // 取得対象カレンダーの直近 7 日間のイベントを返す
    func fetchCalendarEvents() -> [CalendarEventItem] {
        let targetIds = Set(configService.config.targetCalendarIds)
        let allCalendars = calendarService.fetchCalendars()
        let calendars = targetIds.isEmpty ? nil : allCalendars.filter { targetIds.contains($0.calendarIdentifier) }
        return calendarService.fetchEvents(calendars: calendars).map { event in
            // eventIdentifier が nil の場合はタイトル・開始日・カレンダー ID のハッシュで代替する
            let eventId = event.eventIdentifier
                ?? "\(event.calendar.calendarIdentifier)-\(event.title ?? "")-\(event.startDate.timeIntervalSince1970)"
            return CalendarEventItem(
                id: eventId,
                calendarId: event.calendar.calendarIdentifier,
                title: event.title ?? "(タイトルなし)",
                startTime: event.startDate,
                endTime: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                notes: event.notes
            )
        }
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
        let allEvents = fetchCalendarEvents()
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
                    description: e.notes
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

    // RSS フィードアイテム（内部用）
    private struct RssItem {
        let title: String
        let summary: String?
        let url: String?
        let publishedAt: Date
    }

    // EKSourceType を表示用文字列に変換する
    private func sourceTypeDescription(_ type: EKSourceType) -> String {
        switch type {
        case .local: return "ローカル"
        case .exchange: return "Exchange"
        case .calDAV: return "CalDAV"
        case .mobileMe: return "iCloud"
        case .subscribed: return "購読"
        case .birthdays: return "誕生日"
        @unknown default: return "不明"
        }
    }

    // CGColor を "#RRGGBB" 16進数文字列に変換する
    private func colorHex(_ cgColor: CGColor?) -> String? {
        guard let cgColor,
              let components = cgColor.components,
              components.count >= 3
        else { return nil }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
