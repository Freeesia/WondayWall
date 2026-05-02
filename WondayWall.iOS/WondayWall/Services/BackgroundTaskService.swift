import Foundation
import BackgroundTasks

// バックグラウンド定期生成タスクを管理するサービス
final class BackgroundTaskService {
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
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
            return
        }

        let runsPerDay = ScheduleHelper.normalizeRunsPerDay(config.runsPerDay)
        let nextSlot = ScheduleHelper.getNextScheduledSlotAfter(Date(), runsPerDay: runsPerDay)

        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        // 次のスケジュールスロットを earliestBeginDate に設定する
        request.earliestBeginDate = nextSlot

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // スケジュール失敗は致命的ではない（次回起動時に再試行する）
        }
    }

    // BGProcessingTask が起動されたときの処理（AppDelegate から呼ばれる）
    func handle(_ task: BGProcessingTask) {
        // タスク期限切れ時のキャンセルハンドラー
        task.expirationHandler = { [weak self] in
            Task { await self?.coordinator.cancel() }
        }

        Task {
            do {
                _ = try await coordinator.runScheduledIfNeeded()
            } catch {
                // エラーは coordinator 内で履歴保存済み
            }
            // 次回タスクを登録してから完了を通知する
            scheduleNextBackgroundTask()
            task.setTaskCompleted(success: true)
        }
    }

    // アプリ起動時・フォアグラウンド復帰時の生成可否チェック
    // BGProcessingTask が実行されなかった場合の取りこぼし補完として機能する
    func checkAndRunIfNeeded() async {
        guard configService.config.autoGenerationEnabled else { return }
        _ = try? await coordinator.runScheduledIfNeeded()
        scheduleNextBackgroundTask()
    }
}
