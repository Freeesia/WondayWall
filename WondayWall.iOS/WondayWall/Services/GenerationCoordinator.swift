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
        // 手動生成は Standard モードで実行（リアルタイムで八次が必要）
        return await runCore(skipIfNoChanges: skipIfNoChanges, serviceTier: .standard)
    }

    // 定期生成が必要か判定し、必要なら1回だけ生成する
    // スキップの場合は nil を返す
    func runScheduledIfNeeded(now: Date = Date()) async throws -> HistoryItem? {
        let config = configService.config
        guard config.autoGenerationEnabled else { return nil }

        // 接続条件チェック
        if config.wifiOnlyGeneration && !isOnWiFi() { return nil }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
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

        // バックグラウンド定期生成は Flex モードで実行（50% コスト削減，失敗時は Standard にフォールバック）
        return await runCore(skipIfNoChanges: config.skipIfNoChanges, serviceTier: .flex)
    }

    // 現在の生成処理をキャンセルする（バックグラウンドタスクの期限切れ時に呼ぶ）
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // 生成コアロジック（手動・定期両用）
    private func runCore(skipIfNoChanges: Bool, serviceTier: GoogleAiServiceTier) async -> HistoryItem {
        var status: GenerationStatus = .failure
        var photoAssetId: String? = nil
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
                let imageResult = try await googleAiService.generateWallpaper(
                    context: context, serviceTier: serviceTier)
                usedEvents = contextResult.calendarEvents
                usedNews = contextResult.newsTopics
                status = .success

                // 前回生成のアセット識別子を取得する
                let previousAssetId = historyService.getLastSuccessfulGenerated()?.photoAssetId
                // 写真ライブラリの WondayWall アルバムに保存し、前回アセットをアルバムから外す
                photoAssetId = try? await wallpaperService.saveToPhotosAlbum(
                    imagePath: imageResult.filePath,
                    previousAssetId: previousAssetId
                )

                // 通知には絶対パスを渡す
                if configService.config.notificationsEnabled {
                    await notificationService.scheduleSuccessNotification(
                        imagePath: imageResult.filePath)
                }

                // 通知・Photos 保存が完了したらローカルファイルは不要なので削除する
                try? FileManager.default.removeItem(atPath: imageResult.filePath)
            }
        } catch {
            errorSummary = error.localizedDescription
            status = .failure
        }

        let historyItem = HistoryItem(
            executedAt: Date(),
            status: status,
            usedCalendarEvents: usedEvents,
            usedNewsTopics: usedNews,
            usedPrompt: configService.config.userPrompt.isEmpty
                ? nil : configService.config.userPrompt,
            errorSummary: errorSummary,
            photoAssetId: photoAssetId
        )

        historyService.append(historyItem)

        // 通知（失敗時のみここで送信。成功時は上で処理済み）
        if configService.config.notificationsEnabled {
            if status == .failure {
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

    // Wi-Fi 接続中かどうかを確認する
    // NWPathMonitor を使って接続タイプを判定する
    private func isOnWiFi() -> Bool {
        NetworkHelper.isOnWiFi()
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
