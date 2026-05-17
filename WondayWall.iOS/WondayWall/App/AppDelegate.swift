import UIKit
import BackgroundTasks
import UserNotifications
import OSLog

// UIApplicationDelegate — バックグラウンドタスクの登録・通知デリゲート処理を行う
// BGTaskScheduler の登録は application(_:didFinishLaunchingWithOptions:) で行う必要がある
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.studiofreesia.wondaywall", category: "AppDelegate")
    // 通知タップ時に表示する履歴 ID（ContentView に伝達するため静的保持）
    static var pendingHistoryItemID: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.notice("アプリ起動: バックグラウンドタスクハンドラーを登録開始")
        // BGProcessingTask ハンドラーを登録する
        // iOS は起動完了前にこの登録が完了していることを要求する
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskService.taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.logger.notice("BGProcessingTask ハンドラー呼び出し: identifier=\(task.identifier)")
            guard let processingTask = task as? BGProcessingTask else {
                self?.logger.error("BGProcessingTask: 型キャスト失敗")
                task.setTaskCompleted(success: false)
                return
            }
            // AppEnvironment が初期化された後に current が設定される
            if let service = BackgroundTaskService.current {
                self?.logger.notice("BGProcessingTask: BackgroundTaskService.current あり、handle 呼び出し")
                service.handle(processingTask)
            } else {
                self?.logger.error("BGProcessingTask: BackgroundTaskService.current が nil のため完了(失敗)")
                processingTask.setTaskCompleted(success: false)
            }
        }
        logger.notice("BGProcessingTask ハンドラー登録完了: identifier=\(BackgroundTaskService.taskIdentifier)")

        // BGContinuedProcessingTask ハンドラーを登録する
        registerContinuedProcessingTask()

        // 通知デリゲートを設定する
        UNUserNotificationCenter.current().delegate = self

        return true
    }
}

// BGContinuedProcessingTask 登録
extension AppDelegate {
    func registerContinuedProcessingTask() {
        // 前回セッションで残存した可能性のある submit 済みリクエストをキャンセルする。
        // 生成中にアプリが強制終了された場合、リクエストが残り次回 beginTask 時に
        // tooManyPendingTaskRequests が発生して BG 保護なしで生成が走るのを防ぐ。
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: ForegroundBackgroundTaskService.continuedTaskIdentifier
        )
        logger.notice("起動時クリア: BGContinuedProcessingTask 残存リクエストをキャンセル (identifier=\(ForegroundBackgroundTaskService.continuedTaskIdentifier))")
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: ForegroundBackgroundTaskService.continuedTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.logger.notice("BGContinuedProcessingTask ハンドラー呼び出し: identifier=\(task.identifier)")
            guard let continuedTask = task as? BGContinuedProcessingTask else {
                self?.logger.error("BGContinuedProcessingTask: 型キャスト失敗 (taskType=\(type(of: task)))")
                task.setTaskCompleted(success: false)
                return
            }
            if let service = ForegroundBackgroundTaskService.current {
                self?.logger.notice("BGContinuedProcessingTask: ForegroundBackgroundTaskService.current あり、handleContinuedTask 呼び出し")
                service.handleContinuedTask(continuedTask)
            } else {
                self?.logger.error("BGContinuedProcessingTask: ForegroundBackgroundTaskService.current が nil のため完了(失敗)")
                continuedTask.setTaskCompleted(success: false)
            }
        }
        logger.notice("BGContinuedProcessingTask ハンドラー登録完了: identifier=\(ForegroundBackgroundTaskService.continuedTaskIdentifier)")
    }
}

// 通知タップ処理
extension AppDelegate: UNUserNotificationCenterDelegate {
    // フォアグラウンド中の通知表示設定
    // 成功通知はアプリ内 Toast で表示するため、フォアグラウンド中のシステム通知は非表示にする
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    // 通知タップ時の処理
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        // 通知タップ時に履歴詳細へ遷移する
        // NotificationCenter 経由で ContentView に伝達する
        NotificationCenter.default.post(
            name: .openHistoryNotification,
            object: nil
        )
    }
}

extension Notification.Name {
    static let openHistoryNotification = Notification.Name("com.studiofreesia.wondaywall.openHistory")
    // フォアグラウンド中に生成が成功したときに発火する通知
    static let generationSucceededInForeground = Notification.Name("com.studiofreesia.wondaywall.generationSucceededInForeground")
    // BGContinuedProcessingTask の進捗更新通知
    static let generationTaskProgress = Notification.Name("com.studiofreesia.wondaywall.generationTaskProgress")
    // BGContinuedProcessingTask の完了を知らせる通知
    static let generationTaskCompleted = Notification.Name("com.studiofreesia.wondaywall.generationTaskCompleted")
}
