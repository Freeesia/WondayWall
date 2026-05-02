import Foundation
import AuthenticationServices

// Google Calendar への接続と RSS フィードからコンテキストを構築するサービス
final class ContextService {
    // Google OAuth クライアント情報
    private static let clientId =
        "1032289774423-97qnlp8qkh7vca159jvq1ohggcn4qaqm.apps.googleusercontent.com"
    private static let redirectUri =
        "com.googleusercontent.apps.1032289774423-97qnlp8qkh7vca159jvq1ohggcn4qaqm:/"

    // XOR スクランブルされたクライアントシークレット（Windows 版と同一）
    private static let scrambledClientSecret: [UInt8] = [
        16, 33, 39, 42, 7, 52, 122, 25, 21, 77, 7, 95, 38, 87, 23, 72,
        49, 0, 13, 13, 5, 74, 31, 30, 54, 60, 23, 61, 27, 43, 4, 2, 35, 84, 52,
    ]

    private static var clientSecret: String {
        let key = Array("WndyWl".utf8)
        let decoded = scrambledClientSecret.enumerated().map { i, b in
            b ^ key[i % key.count]
        }
        return String(bytes: decoded, encoding: .ascii) ?? ""
    }

    // Keychain キー
    private static let accessTokenKey = "google_access_token"
    private static let refreshTokenKey = "google_refresh_token"
    private static let tokenExpiryKey = "google_token_expiry"

    private let configService: AppConfigService
    private let historyService: HistoryService

    init(configService: AppConfigService, historyService: HistoryService) {
        self.configService = configService
        self.historyService = historyService
    }

    // サイレントにカレンダーへアクセス可能かを確認する
    func canAccessCalendarSilently() async -> Bool {
        guard KeychainHelper.load(forKey: Self.refreshTokenKey) != nil else { return false }
        do {
            _ = try await getValidAccessToken()
            return true
        } catch {
            return false
        }
    }

    // ASWebAuthenticationSession でブラウザ認証を行い、OAuth トークンを取得する
    @MainActor
    func authorizeCalendarInteractive(presentingAnchor: ASPresentationAnchor) async throws {
        var components = URLComponents(
            string: "https://accounts.google.com/o/oauth2/v2/auth"
        )!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(
                name: "scope",
                value: "https://www.googleapis.com/auth/calendar.readonly"
            ),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        let authURL = components.url!
        let callbackScheme =
            "com.googleusercontent.apps.1032289774423-97qnlp8qkh7vca159jvq1ohggcn4qaqm"

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: URLError(.cancelled))
                }
            }
            session.presentationContextProvider = PresentationContextProvider(
                anchor: presentingAnchor
            )
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard
            let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw URLError(.badServerResponse)
        }

        try await exchangeCodeForTokens(code: code)
    }

    // 認証コードをアクセストークンとリフレッシュトークンに交換する
    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        let params = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "code": code,
            "redirect_uri": Self.redirectUri,
            "grant_type": "authorization_code",
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        storeTokens(tokenResponse)
    }

    // リフレッシュトークンで新しいアクセストークンを取得する
    private func refreshAccessToken(refreshToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type"
        )
        let params = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            .data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
        storeTokens(tokenResponse)
        return tokenResponse.accessToken
    }

    // 有効なアクセストークンを返す（期限切れなら自動更新）
    private func getValidAccessToken() async throws -> String {
        let now = Date()
        if let expiryString = KeychainHelper.load(forKey: Self.tokenExpiryKey),
            let expiry = ISO8601DateFormatter().date(from: expiryString),
            expiry > now.addingTimeInterval(60),
            let accessToken = KeychainHelper.load(forKey: Self.accessTokenKey)
        {
            return accessToken
        }
        guard let refreshToken = KeychainHelper.load(forKey: Self.refreshTokenKey) else {
            throw NSError(
                domain: "WondayWall",
                code: 401,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Googleカレンダーが未接続です。設定から接続してください。"
                ]
            )
        }
        return try await refreshAccessToken(refreshToken: refreshToken)
    }

    // トークンを Keychain に保存する
    private func storeTokens(_ response: OAuthTokenResponse) {
        KeychainHelper.save(response.accessToken, forKey: Self.accessTokenKey)
        if let refreshToken = response.refreshToken {
            KeychainHelper.save(refreshToken, forKey: Self.refreshTokenKey)
        }
        if let expiresIn = response.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            KeychainHelper.save(
                ISO8601DateFormatter().string(from: expiry),
                forKey: Self.tokenExpiryKey
            )
        }
    }

    // Google Calendar OAuth 認証情報を削除する
    func disconnectCalendar() {
        KeychainHelper.delete(forKey: Self.accessTokenKey)
        KeychainHelper.delete(forKey: Self.refreshTokenKey)
        KeychainHelper.delete(forKey: Self.tokenExpiryKey)
    }

    // 利用可能なカレンダー一覧を取得する
    func fetchAvailableCalendars() async throws -> [AvailableCalendar] {
        let accessToken = try await getValidAccessToken()
        var request = URLRequest(
            url: URL(
                string: "https://www.googleapis.com/calendar/v3/users/me/calendarList"
            )!
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

    // RSS/Atom フィードからニュースを取得する
    func fetchNews() async -> [NewsTopicItem] {
        let rssSources = configService.config.rssSources
        guard !rssSources.isEmpty else { return [] }
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        let results = await withTaskGroup(of: [RssItem].self) { group in
            for url in rssSources {
                group.addTask { await self.fetchRssItems(from: url, since: weekAgo) }
            }
            var all: [RssItem] = []
            for await items in group { all.append(contentsOf: items) }
            return all
        }
        return results
            .sorted { $0.publishedAt > $1.publishedAt }
            .map {
                NewsTopicItem(
                    id: $0.url ?? $0.title,
                    title: $0.title,
                    summary: $0.summary,
                    url: $0.url,
                    publishedAt: $0.publishedAt,
                    ogpImageUrl: nil
                )
            }
    }

    // 1つの RSS ソースからアイテムを取得してパースする
    private func fetchRssItems(from urlString: String, since: Date) async -> [RssItem] {
        guard let url = URL(string: urlString) else { return [] }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        let parser = RssFeedParser(data: data)
        return parser.parse().filter { $0.publishedAt >= since }
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

    private struct OAuthTokenResponse: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int?
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

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
    fileprivate struct RssItem {
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

// ASWebAuthenticationSession のプレゼンテーションコンテキスト
private final class PresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    let anchor: ASPresentationAnchor
    init(anchor: ASPresentationAnchor) { self.anchor = anchor }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}

// RSS/Atom フィードの XML SAX パーサー
private final class RssFeedParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var items: [ContextService.RssItem] = []

    private var currentTitle = ""
    private var currentLink = ""
    private var currentSummary = ""
    private var currentPubDate = ""
    private var insideItem = false
    private var currentElement = ""
    private var isAtom = false

    init(data: Data) { self.data = data }

    func parse() -> [ContextService.RssItem] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        if elementName == "item" || elementName == "entry" {
            insideItem = true
            isAtom = (elementName == "entry")
            currentTitle = ""
            currentLink = ""
            currentSummary = ""
            currentPubDate = ""
        } else if elementName == "link", isAtom, let href = attributeDict["href"], !href.isEmpty {
            // Atom の <link href="..."> からリンクを取得
            currentLink = href
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch currentElement {
        case "title": currentTitle += trimmed
        case "link" where !isAtom: currentLink += trimmed
        case "description", "summary", "content": currentSummary += trimmed
        case "pubDate", "published", "updated", "dc:date": currentPubDate += trimmed
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "item" || elementName == "entry" else { return }
        insideItem = false
        let date = parseDate(currentPubDate)
        items.append(
            ContextService.RssItem(
                title: currentTitle,
                summary: currentSummary.isEmpty ? nil : currentSummary,
                url: currentLink.isEmpty ? nil : currentLink,
                publishedAt: date
            )
        )
    }

    private func parseDate(_ str: String) -> Date {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: str) { return date }
        }
        return Date()
    }
}
