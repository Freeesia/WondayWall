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

    // 現在生成中かどうか（多重起動ガード用）
    private(set) var isGenerating = false

    // isGenerating 変化時に MainActor で呼ばれるコールバック（AppEnvironment への通知用）
    private var onIsGeneratingChanged: (@MainActor (Bool) -> Void)?

    // キャンセル用タスク
    private var currentTask: Task<HistoryItem, Error>?

    init(
        configService: AppConfigService,
        contextService: ContextService,
        googleAiService: GoogleAiService,
        wallpaperService: WallpaperService,
        historyService: HistoryService,
        notificationService: NotificationService,
        fgBgTaskService: ForegroundBackgroundTaskService,
        onIsGeneratingChanged: (@MainActor (Bool) -> Void)? = nil
    ) {
        self.configService = configService
        self.contextService = contextService
        self.googleAiService = googleAiService
        self.wallpaperService = wallpaperService
        self.historyService = historyService
        self.notificationService = notificationService
        self.fgBgTaskService = fgBgTaskService
        self.onIsGeneratingChanged = onIsGeneratingChanged
    }

    // isGenerating 変化のコールバックを登録する（init 後に AppEnvironment から呼ぶ）
    func setIsGeneratingHandler(_ handler: @escaping @MainActor (Bool) -> Void) {
        onIsGeneratingChanged = handler
    }

    // isGenerating を更新し、コールバック経由で AppEnvironment にも反映する
    private func setIsGenerating(_ value: Bool) async {
        isGenerating = value
        if let cb = onIsGeneratingChanged {
            await MainActor.run { cb(value) }
        }
    }

    // 手動生成を実行する
    // バックグラウンド移行に備えて BGContinuedProcessingTask を開始する
    func runManual() async -> HistoryItem {
        await setIsGenerating(true)
        defer { Task { await self.setIsGenerating(false) } }

        // バックグラウンド移行時の BGContinuedProcessingTask を開始する
        fgBgTaskService.beginTask { [weak self] in
            Task { await self?.handleBackgroundExpiration() }
        }

        // 手動生成は変化がなくても必ず実行し、自動生成の枠も消費する
        let tier: GoogleAiServiceTier = configService.config.forceFlexTier ? .flex : .standard
        return await runCore(skipIfNoChanges: false, serviceTier: tier)
    }

    // 定期生成が必要か判定し、必要なら1回だけ生成する
    // スキップの場合は nil を返す
    func runScheduledIfNeeded(now: Date = Date()) async throws -> HistoryItem? {
        // 多重実行を防止する
        guard !isGenerating else { return nil }
        let config = configService.config
        guard config.autoGenerationEnabled else { return nil }

        // 接続条件チェック
        if config.wifiOnlyGeneration && !isOnWiFi() { return nil }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return nil
        }

        let lastSuccessAt = historyService.getLastSuccessfulGenerated()?.executedAt
        guard ScheduleHelper.isPendingGeneration(
            now: now,
            lastSuccessAt: lastSuccessAt,
            schedule: config.schedule
        ) else {
            return nil
        }

        await setIsGenerating(true)
        defer { Task { await self.setIsGenerating(false) } }

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

        // 生成開始前に「生成中」ステータスの履歴を保存する
        let generatingItem = HistoryItem(
            executedAt: Date(),
            status: .generating
        )
        historyService.append(generatingItem)

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
                    previousAssetId: previousAssetId,
                    maxCount: configService.config.albumMaxCount
                )

                // 通知には絶対パスを渡す
                if configService.config.notificationsEnabled {
                    await notificationService.scheduleSuccessNotification(
                        imagePath: imageResult.filePath)
                }

                // 生成成功を通知する（フォアグラウンド中は ContentView 側で Toast として表示される）
                NotificationCenter.default.post(name: .generationSucceededInForeground, object: nil)

                // 通知・Photos 保存が完了したらローカルファイルは不要なので削除する
                try? FileManager.default.removeItem(atPath: imageResult.filePath)
            }
        } catch {
            errorSummary = error.localizedDescription
            status = .failure
        }

        let historyItem = HistoryItem(
            id: generatingItem.id,
            executedAt: generatingItem.executedAt,
            status: status,
            usedCalendarEvents: usedEvents,
            usedNewsTopics: usedNews,
            usedPrompt: configService.config.userPrompt.isEmpty
                ? nil : configService.config.userPrompt,
            errorSummary: errorSummary,
            photoAssetId: photoAssetId
        )

        // 生成中履歴を最終ステータスで更新する
        historyService.update(historyItem)

        // 通知（失敗時のみここで送信。成功時は上で処理済み）
        if configService.config.notificationsEnabled {
            if status == .failure {
                await notificationService.scheduleFailureNotification(
                    error: errorSummary ?? "不明なエラー"
                )
            }
        }

        // BGContinuedProcessingTask の完了を通知する（iOS 17.4+ 向け）
        let succeeded = status == .success || status == .skipped
        await MainActor.run {
            NotificationCenter.default.post(
                name: .generationTaskCompleted,
                object: nil,
                userInfo: ["success": succeeded]
            )
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
