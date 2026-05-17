import Foundation
import BackgroundTasks
import OSLog

// バックグラウンド定期生成タスクを管理するサービス
final class BackgroundTaskService {
    private let logger = Logger(subsystem: "com.studiofreesia.wondaywall", category: "BackgroundTaskService")
    // Info.plist の BGTaskSchedulerPermittedIdentifiers に登録するタスク ID
    static let taskIdentifier = "com.studiofreesia.wondaywall.generation"

    // AppDelegate のハンドラーから参照できるよう静的に保持する
    // AppEnvironment で初期化後に設定される
    static weak var current: BackgroundTaskService?

    private let configService: AppConfigService
    private let coordinator: GenerationCoordinator

    init(configService: AppConfigService, coordinator: GenerationCoordinator) {
        self.configService = configService
        self.coordinator = coordinator
        BackgroundTaskService.current = self
    }

    // 次回の BGProcessingTaskRequest をスケジュールする
    // 各生成完了後、またはアプリ起動時に呼ぶ
    func scheduleNextBackgroundTask() {
        let config = configService.config
        guard config.autoGenerationEnabled else {
            // 自動生成が無効なら既存のタスクをキャンセルする
            logger.notice("scheduleNextBackgroundTask: 自動生成無効のためキャンセル")
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            return
        }

        let nextSlot = ScheduleHelper.getNextScheduledSlotAfter(Date(), schedule: config.schedule)
        logger.notice("scheduleNextBackgroundTask: 次回スロット=\(nextSlot.formatted(.iso8601))")

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // 次のスケジュールスロットを earliestBeginDate に設定する
        request.earliestBeginDate = nextSlot

        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("scheduleNextBackgroundTask: submit 成功 (identifier=\(Self.taskIdentifier))")
        } catch {
            // スケジュール失敗は致命的ではない（次回起動時に再試行する）
            logger.error("scheduleNextBackgroundTask: submit 失敗 error=\(error.localizedDescription)")
        }
    }

    // 30分後のフォールバックスケジュールを登録する（強制kill・expiration 対策）
    // 同一 taskIdentifier で submit するため、既存のリクエストは上書きされる
    private func scheduleFallbackBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date().addingTimeInterval(30 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("scheduleFallbackBackgroundTask: 30分後フォールバック登録成功")
        } catch {
            logger.error("scheduleFallbackBackgroundTask: submit 失敗 error=\(error.localizedDescription)")
        }
    }

    // BGProcessingTask が起動されたときの処理（AppDelegate から呼ばれる）
    func handle(_ task: BGProcessingTask) {
        logger.notice("handle: BGProcessingTask 受信 identifier=\(task.identifier)")

        // 強制kill・expiration に備えて30分後フォールバックを先に登録する（安全弁）
        // 正常完了時は scheduleNextBackgroundTask() で次スロットへ上書きされる
        scheduleFallbackBackgroundTask()

        // タスク期限切れ時のキャンセルハンドラー
        // 先頭で登録済みの30分後フォールバックはOSに残るため、ここでの再登録は不要
        task.expirationHandler = { [weak self] in
            self?.logger.warning("handle: expirationHandler 呼び出し — タスク期限切れ")
            Task { await self?.coordinator.cancel() }
            // 期限切れを明示的にシステムへ通知する
            task.setTaskCompleted(success: false)
        }

        Task {
            // 前の BGTask 起動から引き継いだ生成処理がまだ動いている場合は
            // フォールバックスケジュールを維持したまま即終了する
            if await coordinator.isGenerating {
                logger.notice("handle: 生成中のため即終了（フォールバックスケジュール維持）")
                task.setTaskCompleted(success: true)
                return
            }

            do {
                let result = try await coordinator.runScheduledIfNeeded()
                if let result {
                    logger.notice("handle: runScheduledIfNeeded 完了 status=\(String(describing: result.status))")
                } else {
                    logger.notice("handle: runScheduledIfNeeded スキップ（生成不要）")
                }
            } catch {
                // エラーは coordinator 内で履歴保存済み
                // 30分後フォールバックが残り、自動再試行される
                logger.error("handle: runScheduledIfNeeded エラー error=\(error.localizedDescription)")
                logger.notice("handle: setTaskCompleted(success: false)")
                task.setTaskCompleted(success: false)
                return
            }

            // 正常完了・スキップ時は次スロットへ上書きしてフォールバックを延長する
            scheduleNextBackgroundTask()
            logger.notice("handle: setTaskCompleted(success: true)")
            task.setTaskCompleted(success: true)
        }
    }
}
