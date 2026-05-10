import Foundation

// 全サービスを保持する DI コンテナ
// SwiftUI 環境経由で各ビューに注入する
@MainActor
final class AppEnvironment: ObservableObject {
    let configService: AppConfigService
    let historyService: HistoryService
    let calendarService: EventKitCalendarService
    let contextService: ContextService
    let googleAiService: GoogleAiService
    let wallpaperService: WallpaperService
    let notificationService: NotificationService
    let fgBgTaskService: ForegroundBackgroundTaskService
    let coordinator: GenerationCoordinator
    let backgroundTaskService: BackgroundTaskService

    // 生成進捗（0-100）。nil は非生成中を表す
    @Published var generationProgress: Int? = nil

    // 生成中かどうか（手動・起動時補完・バックグラウンド両方を含む）
    var isGenerating: Bool { generationProgress != nil }

    init() {
        let config = AppConfigService()
        let history = HistoryService()
        let calendar = EventKitCalendarService()
        let context = ContextService(
            configService: config,
            historyService: history,
            calendarService: calendar
        )
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
        self.calendarService = calendar
        self.contextService = context
        self.googleAiService = googleAi
        self.wallpaperService = wallpaper
        self.notificationService = notifications
        self.fgBgTaskService = fgBg
        self.coordinator = coord
        self.backgroundTaskService = bgTask

        // 全プロパティ初期化後にコールバックを設定する
        Task {
            await coord.setIsGeneratingHandler { [weak self] value in
                guard let self else { return }
                if value {
                    if self.generationProgress == nil {
                        self.generationProgress = 0
                    }
                } else {
                    self.generationProgress = nil
                }
            }
        }

        // 進捗通知を UI 状態へ反映する
        NotificationCenter.default.addObserver(
            forName: .generationTaskProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let progress = notification.userInfo?["progress"] as? Int else { return }
            Task { @MainActor [weak self] in
                self?.generationProgress = max(0, min(100, progress))
            }
        }

        NotificationCenter.default.addObserver(
            forName: .generationTaskCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.generationProgress = nil
            }
        }
    }
}
