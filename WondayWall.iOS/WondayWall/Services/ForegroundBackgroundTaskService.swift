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
        task.expirationHandler = { [weak self] in
            self?.onExpiration?()
            self?.onExpiration = nil
            task.setTaskCompleted(success: false)
        }
        // 生成完了通知を受け取って task.setTaskCompleted を呼ぶ
        NotificationCenter.default.addObserver(
            forName: .generationTaskCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.onExpiration = nil
            let success = notification.userInfo?["success"] as? Bool ?? true
            task.setTaskCompleted(success: success)
        }
    }
}
