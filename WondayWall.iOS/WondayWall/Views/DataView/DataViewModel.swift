import Foundation
import Observation

// データ画面の ViewModel
@MainActor
@Observable
final class DataViewModel {
    var calendarConnected = false
    var availableCalendars: [AvailableCalendar] = []
    var upcomingEvents: [CalendarEventItem] = []
    var recentNews: [NewsTopicItem] = []
    var isLoadingCalendar = false
    var isLoadingNews = false
    var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // カレンダー接続状態を確認する
    func checkCalendarConnection() async {
        calendarConnected = await environment.contextService.canAccessCalendarSilently()
    }

    // 利用可能なカレンダー一覧を取得する
    func loadAvailableCalendars() async {
        isLoadingCalendar = true
        defer { isLoadingCalendar = false }
        do {
            availableCalendars = try await environment.contextService.fetchAvailableCalendars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 直近のカレンダーイベントを取得する
    func loadUpcomingEvents() async {
        do {
            upcomingEvents = try await environment.contextService.fetchCalendarEvents()
        } catch {
            // エラーは接続確認で処理済み
        }
    }

    // ニュース一覧を取得する
    func loadNews() async {
        isLoadingNews = true
        defer { isLoadingNews = false }
        recentNews = await environment.contextService.fetchNews()
    }

    // 全データをリフレッシュする
    func refresh() async {
        await checkCalendarConnection()
        if calendarConnected {
            async let calendars: Void = loadAvailableCalendars()
            async let events: Void = loadUpcomingEvents()
            _ = await (calendars, events)
        }
        await loadNews()
    }
}
