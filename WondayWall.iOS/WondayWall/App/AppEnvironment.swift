import Foundation

// 全サービスを保持する DI コンテナ
// SwiftUI 環境経由で各ビューに注入する
@MainActor
final class AppEnvironment: ObservableObject {
    let configService: AppConfigService
    let historyService: HistoryService
    let contextService: ContextService
    let googleAiService: GoogleAiService
    let wallpaperService: WallpaperService
    let notificationService: NotificationService
    let fgBgTaskService: ForegroundBackgroundTaskService
    let coordinator: GenerationCoordinator
    let backgroundTaskService: BackgroundTaskService

    init() {
        let config = AppConfigService()
        let history = HistoryService()
        let context = ContextService(configService: config, historyService: history)
        let googleAi = GoogleAiService(configService: config)
        let wallpaper = WallpaperService()
        let notifications = NotificationService()
        let fgBg = ForegroundBackgroundTaskService()
        let coord = GenerationCoordinator(
            configService: config,
            contextService: context,
            googleAiService: googleAi,
            wallpaperService: wallpaper,
            historyService: history,
            notificationService: notifications,
            fgBgTaskService: fgBg
        )
        let bgTask = BackgroundTaskService(configService: config, coordinator: coord)

        self.configService = config
        self.historyService = history
        self.contextService = context
        self.googleAiService = googleAi
        self.wallpaperService = wallpaper
        self.notificationService = notifications
        self.fgBgTaskService = fgBg
        self.coordinator = coord
        self.backgroundTaskService = bgTask
    }
}
