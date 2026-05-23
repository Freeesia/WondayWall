import Foundation
import BackgroundTasks
import OSLog

// 手動生成・起動時生成中にアプリがバックグラウンドへ移った場合の継続を管理するサービス
// BGContinuedProcessingTask を使い、ユーザーに進捗を明示しながら処理を継続する
final class ForegroundBackgroundTaskService {
    private let logger = Logger(subsystem: "com.studiofreesia.wondaywall", category: "ForegroundBackgroundTaskService")
    // BGContinuedProcessingTask の識別子（Info.plist に登録済み）
    static let continuedTaskIdentifier = "com.studiofreesia.wondaywall.manual"

    // AppDelegate のハンドラーから参照できるよう静的に保持する
    static weak var current: ForegroundBackgroundTaskService?

    private var onExpiration: (() -> Void)?
    private var completionObserver: NSObjectProtocol?
    private var progressObserver: NSObjectProtocol?
    // weak ではなく strong で保持する。weak にするとシステムがタスクオブジェクトへの参照を
    // 手放した時点で activeTask が nil になり、app の BG 保護が失われる。
    private var activeTask: BGContinuedProcessingTask?
    private var isTaskCompleted = false

    init() {
        ForegroundBackgroundTaskService.current = self
    }

    // フォアグラウンド開始の生成を BGContinuedProcessingTask 経由で開始する
    func beginTask(onExpiration: @escaping () -> Void) {
        self.onExpiration = onExpiration
        logger.notice("beginTask: BGContinuedProcessingTaskRequest を submit 試行 (identifier=\(Self.continuedTaskIdentifier))")
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedTaskIdentifier,
            title: "壁紙を生成中",
            subtitle: "壁紙候補画像を作成しています"
        )
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("beginTask: submit 成功")
        } catch {
            // submit 失敗は無視する（生成処理自体は続行する）
            logger.error("beginTask: submit 失敗 error=\(error.localizedDescription) (\(String(describing: (error as NSError).code)))")
        }

        // 生成完了通知を beginTask 時点で監視する。
        // handleContinuedTask より前（FG中）に完了した場合は submit 済みリクエストをキャンセルし、
        // handleContinuedTask より後（BG中）に完了した場合は task.setTaskCompleted を呼ぶ。
        // ※ handleContinuedTask 内で completionObserver を設定すると FG完了時に通知を取りこぼす。
        completionObserver = NotificationCenter.default.addObserver(
            forName: .generationTaskCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let success = notification.userInfo?["success"] as? Bool ?? true
            self.logger.notice("generationTaskCompleted 通知受信: success=\(success), hasActiveTask=\(self.activeTask != nil)")
            if self.activeTask != nil {
                // BG移行後に完了 → BGContinuedProcessingTask を完了させる
                self.completeTask(success: success)
            } else {
                // FG中に完了 → 未処理の submit リクエストをキャンセルする
                self.logger.notice("FG完了: BGContinuedProcessingTask リクエストをキャンセル (identifier=\(Self.continuedTaskIdentifier))")
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.continuedTaskIdentifier)
                self.onExpiration = nil
                self.clearObservers()
            }
        }
    }

    // BGContinuedProcessingTask ハンドラー（AppDelegate から呼ばれる）
    func handleContinuedTask(_ task: BGContinuedProcessingTask) {
        logger.notice("handleContinuedTask: タスク受信 identifier=\(task.identifier)")
        // completionObserver は beginTask で設定済みのため、ここでは progressObserver のみ再設定する。
        // clearObservers() を呼ぶと completionObserver まで消えてしまうため呼ばない。
        if let token = progressObserver {
            NotificationCenter.default.removeObserver(token)
            progressObserver = nil
        }
        activeTask = task
        isTaskCompleted = false
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 0

        task.expirationHandler = { [weak self] in
            self?.logger.warning("handleContinuedTask: expirationHandler 呼び出し — タスク期限切れ")
            self?.onExpiration?()
            self?.completeTask(success: false)
        }

        progressObserver = NotificationCenter.default.addObserver(
            forName: .generationTaskProgress,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                let progress = notification.userInfo?["progress"] as? Int,
                let task = self.activeTask,
                !self.isTaskCompleted
            else {
                return
            }
            let clamped = max(0, min(100, progress))
            let message = notification.userInfo?["message"] as? String ?? ""
            self.logger.debug("progress 更新: \(clamped)% message=\(message)")
            // Dynamic Island へ単調増加の進捗を表示する
            task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(clamped))
        }
        logger.notice("handleContinuedTask: activeTask 設定完了、progressObserver 登録完了")
    }

    private func completeTask(success: Bool) {
        guard !isTaskCompleted else {
            logger.warning("completeTask: 既に完了済みのため無視 success=\(success)")
            return
        }
        logger.notice("completeTask: タスク完了 success=\(success)")
        isTaskCompleted = true
        onExpiration = nil
        if let task = activeTask {
            task.progress.completedUnitCount = 100
            task.setTaskCompleted(success: success)
        } else {
            logger.warning("completeTask: activeTask が nil — setTaskCompleted を呼べない")
        }
        activeTask = nil
        clearObservers()
    }

    private func clearObservers() {
        if let token = completionObserver {
            NotificationCenter.default.removeObserver(token)
            completionObserver = nil
        }
        if let token = progressObserver {
            NotificationCenter.default.removeObserver(token)
            progressObserver = nil
        }
    }
}
