import Foundation
import Observation
import EventKit
import SwiftSoup

// 設定画面の ViewModel
@MainActor
@Observable
final class SettingsViewModel {
    // @Bindable で直接バインドできるよう stored property にする
    // didSet で configService への保存を行う
    var config: AppConfig {
        didSet { environment.configService.update { $0 = config } }
    }

    // Google AI API キー（Keychain に保存；@Bindable でバインドするため stored property にする）
    var googleAiApiKey: String {
        didSet { environment.configService.googleAiApiKey = googleAiApiKey }
    }

    // カレンダーアクセス権限
    var calendarAuthStatus: EKAuthorizationStatus = .notDetermined
    var isRequestingCalendarAccess = false
    // 端末に登録されているカレンダー一覧
    var availableCalendars: [CalendarSourceItem] = []
    var showAddRssSheet = false
    var newRssURL = ""
    var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.config = environment.configService.config
        self.googleAiApiKey = environment.configService.googleAiApiKey
        self.calendarAuthStatus = environment.calendarService.authorizationStatus()
    }

    // カレンダー一覧を取得する
    func loadAvailableCalendars() {
        availableCalendars = environment.contextService.fetchAvailableCalendars()
    }

    // EventKit アクセス許可をリクエストする
    func requestCalendarAccess() async {
        isRequestingCalendarAccess = true
        defer { isRequestingCalendarAccess = false }
        do {
            _ = try await environment.calendarService.requestAccess()
            calendarAuthStatus = environment.calendarService.authorizationStatus()
            loadAvailableCalendars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // カレンダーの選択状態をトグルする
    func toggleCalendar(_ calendarId: String) {
        if config.targetCalendarIds.contains(calendarId) {
            config.targetCalendarIds.removeAll { $0 == calendarId }
        } else {
            config.targetCalendarIds.append(calendarId)
        }
    }

    // RSS ソースを追加する
    func addRssSource() async {
        let sourceURL = newRssURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceURL.isEmpty else { return }
        guard let url = URL(string: sourceURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            errorMessage = "有効なサイトURLまたはRSS URLを入力してください。"
            return
        }

        let resolvedRssURL = await resolveRssSourceURL(from: sourceURL, sourceURLObject: url)
        guard let resolvedRssURL else {
            errorMessage = "指定のサイトからニュース情報を得られませんでした。"
            return
        }

        if !config.rssSources.contains(resolvedRssURL) {
            config.rssSources.append(resolvedRssURL)
        }
        newRssURL = ""
        showAddRssSheet = false
        errorMessage = nil
    }

    // RSS ソースを削除する
    func removeRssSource(at offsets: IndexSet) {
        config.rssSources.remove(atOffsets: offsets)
    }

    private func resolveRssSourceURL(from sourceURL: String, sourceURLObject: URL) async -> String? {
        if isLikelyRssURL(sourceURLObject) {
            return sourceURL
        }

        var request = URLRequest(url: sourceURLObject, timeoutInterval: 10)
        request.setValue(
            "WondayWall/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let html = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(html, sourceURLObject.absoluteString),
              let linkElements = try? doc.select("link[rel][type][href]") else {
            return nil
        }

        for link in linkElements.array() {
            guard let rel = try? link.attr("rel"),
                  containsToken(rel, token: "alternate") else { continue }
            guard let type = try? link.attr("type"),
                  isFeedContentType(type) else { continue }

            if let absoluteHref = try? link.attr("abs:href"), !absoluteHref.isEmpty {
                return absoluteHref
            }

            guard let href = try? link.attr("href"), !href.isEmpty else { continue }
            if let resolvedURL = URL(string: href, relativeTo: sourceURLObject)?.absoluteURL.absoluteString {
                return resolvedURL
            }
        }

        return nil
    }

    private func containsToken(_ source: String, token: String) -> Bool {
        source.components(separatedBy: .whitespacesAndNewlines)
            .contains { $0.caseInsensitiveCompare(token) == .orderedSame }
    }

    private func isFeedContentType(_ type: String) -> Bool {
        type.localizedCaseInsensitiveContains("application/rss+xml")
            || type.localizedCaseInsensitiveContains("application/atom+xml")
    }

    private func isLikelyRssURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        if path.hasSuffix(".xml")
            || path.hasSuffix(".rss")
            || path.hasSuffix(".atom") {
            return true
        }

        let query = (url.query ?? "").lowercased()
        return path.contains("feed")
            || path.contains("rss")
            || path.contains("atom")
            || query.contains("feed")
            || query.contains("rss")
            || query.contains("atom")
    }

    // 自動生成設定変更時にバックグラウンドタスクを更新する
    func onAutoGenerationChanged() {
        environment.backgroundTaskService.scheduleNextBackgroundTask()
    }

    // カレンダーアクセスが許可されているか
    var isCalendarAccessGranted: Bool {
        calendarAuthStatus == .fullAccess
    }

    // カレンダーアクセスが明示的に拒否されているか
    var isCalendarAccessDenied: Bool {
        calendarAuthStatus == .denied
    }
}
