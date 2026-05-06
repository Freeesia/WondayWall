import Foundation
import UIKit

// 手動生成中にアプリがバックグラウンドへ移った場合の短時間継続を管理するサービス
final class ForegroundBackgroundTaskService {
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var onExpiration: (() -> Void)?

    // バックグラウンドタスクを開始する
    // expiration handler でタスクが打ち切られた場合に onExpiration が呼ばれる
    func beginTask(onExpiration: @escaping () -> Void) {
        // 既存のタスクがある場合は先に終了させる
        endTask()
        self.onExpiration = onExpiration
        backgroundTaskID = UIApplication.shared.beginBackgroundTask { [weak self] in
            // 期限切れ時は後片付けして endTask を呼ぶ
            self?.onExpiration?()
            self?.endTask()
        }
    }

    // バックグラウンドタスクを終了する
    func endTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        onExpiration = nil
    }
}
