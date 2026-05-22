import Foundation
import OSLog

// 壁紙生成処理全体を統括するサービス
// actor によって多重実行を防止する
actor GenerationCoordinator {
    private let logger = Logger(subsystem: "com.studiofreesia.wondaywall", category: "GenerationCoordinator")
    private let configService: AppConfigService
    private let contextService: ContextService
    private let googleAiService: any GoogleAiServiceProtocol
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
        googleAiService: any GoogleAiServiceProtocol,
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

    // 現在時刻で定期生成が必要かどうかを返す（起動時・復帰時の事前確認用）
    func isScheduledGenerationNeeded(now: Date = Date()) -> Bool {
        guard !isGenerating else {
            logger.notice("isScheduledGenerationNeeded: isGenerating=true → スキップ")
            return false
        }

        // 前回の生成が中断されている場合は、設定に関わらずなるはやで再実行する
        if historyService.getPendingGeneratingItem() != nil || historyService.getGeneratingWithPrompt() != nil {
            logger.notice("isScheduledGenerationNeeded: 中断中の生成あり → 再実行")
            return true
        }

        let config = configService.config
        guard config.autoGenerationEnabled else {
            logger.notice("isScheduledGenerationNeeded: autoGenerationEnabled=false → スキップ")
            return false
        }
        if config.wifiOnlyGeneration && !isOnWiFi() {
            logger.warning("isScheduledGenerationNeeded: wifiOnlyGeneration=true かつ WiFi 未接続 → スキップ")
            return false
        }
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            logger.warning("isScheduledGenerationNeeded: 低電力モード有効 → スキップ")
            return false
        }

        let lastRunAt = historyService.getLastCompletedRun()?.executedAt
        let needed = ScheduleHelper.isPendingGeneration(
            now: now,
            lastRunAt: lastRunAt,
            schedule: config.schedule
        )
        if needed {
            let lastStr = lastRunAt.map { $0.formatted(.iso8601) } ?? "nil"
            logger.notice("isScheduledGenerationNeeded: 生成必要 lastRunAt=\(lastStr, privacy: .public) now=\(now.formatted(.iso8601), privacy: .public)")
        } else {
            let lastStr = lastRunAt.map { $0.formatted(.iso8601) } ?? "nil"
            logger.notice("isScheduledGenerationNeeded: スケジュール上不要 lastRunAt=\(lastStr, privacy: .public) now=\(now.formatted(.iso8601), privacy: .public)")
        }
        return needed
    }

    // 定期生成が必要か判定し、必要なら1回だけ生成する
    // スキップの場合は nil を返す
    func runScheduledIfNeeded(now: Date = Date()) async throws -> HistoryItem? {
        guard isScheduledGenerationNeeded(now: now) else { return nil }

        let config = configService.config

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
        let coreStartTime = Date()
        let tierStr = serviceTier == .flex ? "flex" : "standard"
        logger.notice("runCore 開始 tier=\(tierStr, privacy: .public) skipIfNoChanges=\(skipIfNoChanges, privacy: .public)")

        var status: GenerationStatus = .failure
        var photoAssetId: String? = nil
        var usedEvents: [CalendarEventItem]? = nil
        var usedNews: [NewsTopicItem]? = nil
        var errorSummary: String? = nil
        var generatedPrompt: String? = nil

        // 再開チェック: プロンプト生成済み（generatingPromptReady）→ 画像生成のみ再試行
        let resumable = historyService.getGeneratingWithPrompt()

        // generatingItem の決定（再開 | プロンプト生成前の再起動 | 新規）
        let generatingItem: HistoryItem
        if let resumable {
            generatingItem = resumable
        } else if let pending = historyService.getPendingGeneratingItem() {
            let retrying = HistoryItem(id: pending.id, executedAt: Date(), status: .generating)
            historyService.update(retrying)
            generatingItem = retrying
        } else {
            let newItem = HistoryItem(executedAt: Date(), status: .generating)
            historyService.append(newItem)
            generatingItem = newItem
        }

        let isResume = resumable != nil

        do {
            await postProgress(0.01, message: isResume ? "処理を再開中" : "処理を開始")

            // コンテキスト取得（再開時は進捗通知なし）
            let contextResult = await contextService.buildContext { [weak self] progress, message in
                guard let self, !isResume else { return }
                Task { await self.postProgress(progress, message: message) }
            }
            let context = contextResult.promptContext

            // 変化がなければスキップする判定（再開時はスキップしない）
            if !isResume
                && skipIfNoChanges
                && contextResult.calendarEvents.isEmpty
                && !hasNewsChanged(
                    current: contextResult.newsTopics,
                    history: historyService.load()
                )
            {
                status = .skipped
            } else {
                // ステップ 1: プロンプト生成 or 保存済みプロンプト再利用
                let promptResult: PromptGenerationResult
                if let savedPrompt = resumable?.generatedPrompt {
                    // 再開フロー: 保存済みプロンプトと採用ニュース ID を再利用（中間保存① はスキップ）
                    let selectedIds = resumable?.usedNewsTopics?.map { $0.id } ?? []
                    promptResult = PromptGenerationResult(imagePrompt: savedPrompt, selectedNewsIds: selectedIds)
                    generatedPrompt = savedPrompt
                } else {
                    // 通常フロー: テキストモデルで画像プロンプトを生成
                    logger.notice("runCore ステップ1: プロンプト生成 開始")
                    let step1Start = Date()
                    let result = try await googleAiService.generatePrompt(
                        context: context,
                        serviceTier: serviceTier,
                        onProgress: { [weak self] progress, message in
                            guard let self else { return }
                            let scaled = 0.35 + progress * 0.30  // 全体の 0.35 → 0.65 の範囲で報告
                            Task { await self.postProgress(scaled, message: message) }
                        }
                    )
                    logger.notice("runCore ステップ1: プロンプト生成 完了 elapsed=\(String(format: "%.1f", Date().timeIntervalSince(step1Start)), privacy: .public)s")
                    generatedPrompt = result.imagePrompt
                    promptResult = result

                    // 中間保存①: generatingPromptReady（プロンプト生成完了・画像 API 呼び出し前）
                    let adoptedNewsForPrompt = contextResult.newsTopics.filter {
                        result.selectedNewsIds.contains($0.id)
                    }
                    historyService.update(HistoryItem(
                        id: generatingItem.id,
                        executedAt: generatingItem.executedAt,
                        status: .generatingPromptReady,
                        usedCalendarEvents: contextResult.calendarEvents,
                        usedNewsTopics: adoptedNewsForPrompt,
                        usedPrompt: configService.config.userPrompt.isEmpty ? nil : configService.config.userPrompt,
                        generatedPrompt: result.imagePrompt
                    ))
                }

                // 採用ニュースを決定（再開: resumable.usedNewsTopics / 新規: selectedNewsIds でフィルタ）
                let adoptedNews = resumable?.usedNewsTopics
                    ?? contextResult.newsTopics.filter { promptResult.selectedNewsIds.contains($0.id) }

                // ステップ 1.5: 採用ニュースの OGP 画像をダウンロードする
                let contextWithOgp = await googleAiService.fetchOgpImages(
                    context: context,
                    selectedNewsIds: promptResult.selectedNewsIds
                )

                // 中間保存②: generatingImageRequested（画像 API 呼び出し直前）
                // ここで BG kill された場合は起動時に failure 変換されスロット消費済みとなる
                historyService.update(HistoryItem(
                    id: generatingItem.id,
                    executedAt: generatingItem.executedAt,
                    status: .generatingImageRequested,
                    usedCalendarEvents: resumable?.usedCalendarEvents ?? contextResult.calendarEvents,
                    usedNewsTopics: adoptedNews,
                    usedPrompt: resumable?.usedPrompt ?? (configService.config.userPrompt.isEmpty ? nil : configService.config.userPrompt),
                    generatedPrompt: promptResult.imagePrompt
                ))

                // ステップ 2: 画像モデルで壁紙を生成
                logger.notice("runCore ステップ2: 画像生成 開始")
                let step2Start = Date()
                let imageResult = try await googleAiService.generateImageFromPrompt(
                    imagePrompt: promptResult.imagePrompt,
                    context: contextWithOgp,
                    serviceTier: serviceTier,
                    onProgress: { [weak self] progress, message in
                        guard let self else { return }
                        let scaled = 0.65 + progress * 0.30  // 全体の 0.65 → 0.95 の範囲で報告
                        Task { await self.postProgress(scaled, message: message) }
                    }
                )
                logger.notice("runCore ステップ2: 画像生成 完了 elapsed=\(String(format: "%.1f", Date().timeIntervalSince(step2Start)), privacy: .public)s")
                usedEvents = resumable?.usedCalendarEvents ?? contextResult.calendarEvents
                usedNews = adoptedNews
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
                await postProgress(1.0, message: "処理完了")
            }
        } catch {
            let elapsed = Date().timeIntervalSince(coreStartTime)
            logger.error("runCore エラー elapsed=\(String(format: "%.1f", elapsed), privacy: .public)s error=\(error.localizedDescription, privacy: .public)")
            errorSummary = error.localizedDescription
            status = .failure
        }

        let historyItem = HistoryItem(
            id: generatingItem.id,
            executedAt: generatingItem.executedAt,
            status: status,
            usedCalendarEvents: usedEvents,
            usedNewsTopics: usedNews,
            usedPrompt: resumable?.usedPrompt ?? (configService.config.userPrompt.isEmpty ? nil : configService.config.userPrompt),
            errorSummary: errorSummary,
            photoAssetId: photoAssetId,
            generatedPrompt: generatedPrompt
        )

        // 生成中履歴を最終ステータスで更新する
        historyService.update(historyItem)

        let totalElapsed = Date().timeIntervalSince(coreStartTime)
        logger.notice("runCore 完了 status=\(status.rawValue, privacy: .public) elapsed=\(String(format: "%.1f", totalElapsed), privacy: .public)s")

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

    // BGContinuedProcessingTask 向けに生成進捗を通知する
    private func postProgress(_ value: Double, message: String) async {
        let clamped = max(0, min(100, Int((value * 100).rounded())))
        await MainActor.run {
            NotificationCenter.default.post(
                name: .generationTaskProgress,
                object: nil,
                userInfo: [
                    "progress": clamped,
                    "message": message,
                ]
            )
        }
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
