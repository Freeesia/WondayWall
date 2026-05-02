import Foundation

// 壁紙生成処理全体を統括するサービス
// actor によって多重実行を防止する
actor GenerationCoordinator {
    private let configService: AppConfigService
    private let contextService: ContextService
    private let googleAiService: GoogleAiService
    private let wallpaperService: WallpaperService
    private let historyService: HistoryService
    private let notificationService: NotificationService
    private let fgBgTaskService: ForegroundBackgroundTaskService

    // 現在生成中かどうか（UI 表示用）
    private(set) var isGenerating = false

    // キャンセル用タスク
    private var currentTask: Task<HistoryItem, Error>?

    init(
        configService: AppConfigService,
        contextService: ContextService,
        googleAiService: GoogleAiService,
        wallpaperService: WallpaperService,
        historyService: HistoryService,
        notificationService: NotificationService,
        fgBgTaskService: ForegroundBackgroundTaskService
    ) {
        self.configService = configService
        self.contextService = contextService
        self.googleAiService = googleAiService
        self.wallpaperService = wallpaperService
        self.historyService = historyService
        self.notificationService = notificationService
        self.fgBgTaskService = fgBgTaskService
    }

    // 手動生成を実行する
    // バックグラウンド移行に備えて beginBackgroundTask を開始する
    func runManual() async -> HistoryItem {
        isGenerating = true
        defer { isGenerating = false }

        // バックグラウンド移行時の短時間継続タスクを開始
        fgBgTaskService.beginTask { [weak self] in
            Task { await self?.handleBackgroundExpiration() }
        }
        defer { fgBgTaskService.endTask() }

        let skipIfNoChanges = configService.config.skipIfNoChanges
        return await runCore(skipIfNoChanges: skipIfNoChanges)
    }

    // 定期生成が必要か判定し、必要なら1回だけ生成する
    // スキップの場合は nil を返す
    func runScheduledIfNeeded(now: Date = Date()) async throws -> HistoryItem? {
        let config = configService.config
        guard config.autoGenerationEnabled else { return nil }

        // 接続条件チェック
        if config.wifiOnlyGeneration && !isOnWiFi() { return nil }
        if config.skipOnLowPowerMode && ProcessInfo.processInfo.isLowPowerModeEnabled {
            return nil
        }

        let runsPerDay = ScheduleHelper.normalizeRunsPerDay(config.runsPerDay)
        let lastSuccessAt = historyService.getLastSuccessfulGenerated()?.executedAt
        guard ScheduleHelper.isPendingGeneration(
            now: now,
            lastSuccessAt: lastSuccessAt,
            runsPerDay: runsPerDay
        ) else {
            return nil
        }

        isGenerating = true
        defer { isGenerating = false }

        return await runCore(skipIfNoChanges: config.skipIfNoChanges)
    }

    // 現在の生成処理をキャンセルする（バックグラウンドタスクの期限切れ時に呼ぶ）
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // 生成コアロジック（手動・定期両用）
    private func runCore(skipIfNoChanges: Bool) async -> HistoryItem {
        var status: GenerationStatus = .failure
        var imagePath: String? = nil
        var usedEvents: [CalendarEventItem]? = nil
        var usedNews: [NewsTopicItem]? = nil
        var errorSummary: String? = nil

        do {
            let contextResult = await contextService.buildContext()
            let context = contextResult.promptContext

            // 変化がなければスキップする判定
            if skipIfNoChanges
                && contextResult.calendarEvents.isEmpty
                && !hasNewsChanged(
                    current: contextResult.newsTopics,
                    history: historyService.load()
                )
            {
                status = .skipped
            } else {
                let imageResult = try await googleAiService.generateWallpaper(context: context)
                imagePath = imageResult.filePath
                usedEvents = contextResult.calendarEvents
                usedNews = contextResult.newsTopics
                status = .success

                // 設定で自動保存が有効なら写真ライブラリに保存する
                if configService.config.saveToPhotosEnabled {
                    try? await wallpaperService.saveToPhotos(imagePath: imageResult.filePath)
                }
            }
        } catch {
            errorSummary = error.localizedDescription
            status = .failure
        }

        let historyItem = HistoryItem(
            executedAt: Date(),
            status: status,
            imagePath: imagePath,
            usedCalendarEvents: usedEvents,
            usedNewsTopics: usedNews,
            usedPrompt: configService.config.userPrompt.isEmpty
                ? nil : configService.config.userPrompt,
            errorSummary: errorSummary
        )

        historyService.append(historyItem)

        // 通知
        if configService.config.notificationsEnabled {
            if status == .success {
                await notificationService.scheduleSuccessNotification(imagePath: imagePath)
            } else if status == .failure {
                await notificationService.scheduleFailureNotification(
                    error: errorSummary ?? "不明なエラー"
                )
            }
        }

        return historyItem
    }

    // バックグラウンドタスクの期限切れ時の後片付け
    private func handleBackgroundExpiration() {
        cancel()
    }

    // Wi-Fi 接続中かどうかを確認する（簡易チェック）
    private func isOnWiFi() -> Bool {
        // Network.framework を使った実装は NWPathMonitor が必要だが、
        // ここでは常に true を返し呼び出し元に判断を委ねる
        // 本番実装では NWPathMonitor を使って接続タイプを判定すること
        true
    }

    // ニューストピックに変化があるかを判定する
    private func hasNewsChanged(
        current: [NewsTopicItem],
        history: [HistoryItem]
    ) -> Bool {
        guard let lastHistory = history.first(where: { $0.isSuccess && !$0.isSkipped }),
            let lastNews = lastHistory.usedNewsTopics, !lastNews.isEmpty
        else {
            return true
        }

        let previousKeys = Set(lastNews.compactMap { $0.url ?? $0.title })
        let currentKeys = Set(current.compactMap { $0.url ?? $0.title })
        return previousKeys != currentKeys
    }
}
