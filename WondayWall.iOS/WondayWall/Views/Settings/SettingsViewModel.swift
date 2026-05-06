import Foundation
import Observation
import EventKit

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
    func addRssSource() {
        let url = newRssURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        if !config.rssSources.contains(url) {
            config.rssSources.append(url)
        }
        newRssURL = ""
        showAddRssSheet = false
    }

    // RSS ソースを削除する
    func removeRssSource(at offsets: IndexSet) {
        config.rssSources.remove(atOffsets: offsets)
    }

    // 自動生成設定変更時にバックグラウンドタスクを更新する
    func onAutoGenerationChanged() {
        environment.backgroundTaskService.scheduleNextBackgroundTask()
    }

    // カレンダーアクセスが許可されているか
    var isCalendarAccessGranted: Bool {
        if #available(iOS 17.0, *) {
            return calendarAuthStatus == .fullAccess
        } else {
            return calendarAuthStatus == .authorized
        }
    }
}
