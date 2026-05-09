import Foundation
import BackgroundTasks

// 手動生成・起動時生成中にアプリがバックグラウンドへ移った場合の継続を管理するサービス
// BGContinuedProcessingTask を使い、ユーザーに進捗を明示しながら処理を継続する
final class ForegroundBackgroundTaskService {
    // BGContinuedProcessingTask の識別子（Info.plist に登録済み）
    static let continuedTaskIdentifier = "com.studiofreesia.wondaywall.manual"

    // AppDelegate のハンドラーから参照できるよう静的に保持する
    static weak var current: ForegroundBackgroundTaskService?

    private var onExpiration: (() -> Void)?
    private var completionObserver: NSObjectProtocol?
    private var progressObserver: NSObjectProtocol?
    private weak var activeTask: BGContinuedProcessingTask?
    private var isTaskCompleted = false

    init() {
        ForegroundBackgroundTaskService.current = self
    }

    // フォアグラウンド開始の生成を BGContinuedProcessingTask 経由で開始する
    func beginTask(onExpiration: @escaping () -> Void) {
        self.onExpiration = onExpiration
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedTaskIdentifier,
            title: "壁紙を生成中",
            subtitle: "壁紙候補画像を作成しています"
        )
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // submit 失敗は無視する（生成処理自体は続行する）
        }
    }

    // BGContinuedProcessingTask ハンドラー（AppDelegate から呼ばれる）
    func handleContinuedTask(_ task: BGContinuedProcessingTask) {
        clearObservers()
        activeTask = task
        isTaskCompleted = false
        task.progress.totalUnitCount = 100
        task.progress.completedUnitCount = 0

        task.expirationHandler = { [weak self] in
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
            // Dynamic Island へ単調増加の進捗を表示する
            task.progress.completedUnitCount = max(task.progress.completedUnitCount, Int64(clamped))
        }

        // 生成完了通知を受け取って task.setTaskCompleted を呼ぶ
        completionObserver = NotificationCenter.default.addObserver(
            forName: .generationTaskCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let success = notification.userInfo?["success"] as? Bool ?? true
            self?.completeTask(success: success)
        }
    }

    private func completeTask(success: Bool) {
        guard !isTaskCompleted else { return }
        isTaskCompleted = true
        onExpiration = nil
        if let task = activeTask {
            task.progress.completedUnitCount = 100
            task.setTaskCompleted(success: success)
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
