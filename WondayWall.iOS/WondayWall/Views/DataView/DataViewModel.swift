import Foundation
import Observation

// データ画面の ViewModel
@MainActor
@Observable
final class DataViewModel {
    var calendarAccessGranted = false
    var availableCalendars: [CalendarSourceItem] = []
    var upcomingEvents: [CalendarEventItem] = []
    var recentNews: [NewsTopicItem] = []
    var isLoadingNews = false
    var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    // カレンダーアクセス許可状態を確認する
    func checkCalendarAccess() {
        calendarAccessGranted = environment.contextService.canAccessCalendarSilently()
    }

    // 利用可能なカレンダー一覧を取得する
    func loadAvailableCalendars() {
        availableCalendars = environment.contextService.fetchAvailableCalendars()
    }

    // 直近のカレンダーイベントを取得する
    func loadUpcomingEvents() {
        upcomingEvents = environment.contextService.fetchCalendarEvents()
    }

    // ニュース一覧を取得する
    func loadNews() async {
        isLoadingNews = true
        defer { isLoadingNews = false }
        recentNews = await environment.contextService.fetchNews()
    }

    // 全データをリフレッシュする
    func refresh() async {
        checkCalendarAccess()
        if calendarAccessGranted {
            loadAvailableCalendars()
            loadUpcomingEvents()
        }
        await loadNews()
    }
}
