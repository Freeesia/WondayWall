import Foundation
import Observation

// 設定画面の ViewModel
@MainActor
@Observable
final class SettingsViewModel {
    // @Bindable で直接バインドできるよう stored property にする
    // didSet で configService への保存を行う
    var config: AppConfig {
        didSet { environment.configService.update { $0 = config } }
    }

    var isConnectingCalendar = false
    var isLoadingCalendars = false
    var availableCalendars: [AvailableCalendar] = []
    var showAddRssSheet = false
    var newRssURL = ""
    var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.config = environment.configService.config
    }

    // カレンダー一覧を取得する
    func loadAvailableCalendars() async {
        isLoadingCalendars = true
        defer { isLoadingCalendars = false }
        do {
            availableCalendars = try await environment.contextService.fetchAvailableCalendars()
        } catch {
            // 未接続でも画面を表示するためエラーは無視する
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

    // Google Calendar 接続を解除する
    func disconnectCalendar() {
        environment.contextService.disconnectCalendar()
        availableCalendars = []
        config.targetCalendarIds = []
    }

    // 自動生成設定変更時にバックグラウンドタスクを更新する
    func onAutoGenerationChanged() {
        environment.backgroundTaskService.scheduleNextBackgroundTask()
    }
}
