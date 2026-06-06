import Foundation

// 全サービスを保持する DI コンテナ
// SwiftUI 環境経由で各ビューに注入する
@MainActor
final class AppEnvironment: ObservableObject {
    let configService: AppConfigService
    let historyService: HistoryService
    let calendarService: EventKitCalendarService
    let contextService: ContextService
    let aiService: any AiService
    let wallpaperService: WallpaperService
    let notificationService: NotificationService
    let fgBgTaskService: ForegroundBackgroundTaskService
    let coordinator: GenerationCoordinator
    let backgroundTaskService: BackgroundTaskService

    // 生成進捗（0-100）。nil は非生成中を表す
    @Published var generationProgress: Int? = nil

    // ウィジェットから生成確認シートを開く要求。HomeView が消費する。
    @Published var pendingWidgetGenerationSlotStartedAt: Date? = nil

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
        let ai: any AiService
        #if DEBUG
        if config.debugConfig.useDummyAiService {
            ai = DummyAiService(configService: config)
        } else {
            ai = GoogleAiService(configService: config)
        }
        #else
        ai = GoogleAiService(configService: config)
        #endif
        let wallpaper = WallpaperService()
        let notifications = NotificationService()
        let fgBg = ForegroundBackgroundTaskService()
        let coord = GenerationCoordinator(
            configService: config,
            contextService: context,
            aiService: ai,
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
        self.aiService = ai
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
                Task { await WidgetStateService.refresh(environment: self) }
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
                guard let self else { return }
                self.generationProgress = max(0, min(100, progress))
                Task { await WidgetStateService.refresh(environment: self) }
            }
        }

        NotificationCenter.default.addObserver(
            forName: .generationTaskCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.generationProgress = nil
                Task { await WidgetStateService.refresh(environment: self) }
            }
        }
    }

    func requestWidgetGenerationConfirmation(slotStartedAt: Date) {
        pendingWidgetGenerationSlotStartedAt = slotStartedAt
    }

    func clearWidgetGenerationConfirmationRequest() {
        pendingWidgetGenerationSlotStartedAt = nil
    }
}
