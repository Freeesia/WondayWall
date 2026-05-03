import UIKit
import BackgroundTasks
import UserNotifications
import GoogleSignIn

// UIApplicationDelegate — バックグラウンドタスクの登録・通知デリゲート処理を行う
// BGTaskScheduler の登録は application(_:didFinishLaunchingWithOptions:) で行う必要がある
final class AppDelegate: NSObject, UIApplicationDelegate {
    // 通知タップ時に表示する履歴 ID（ContentView に伝達するため静的保持）
    static var pendingHistoryItemID: UUID?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // BGProcessingTask ハンドラーを登録する
        // iOS は起動完了前にこの登録が完了していることを要求する
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BackgroundTaskService.taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // AppEnvironment が初期化された後に current が設定される
            if let service = BackgroundTaskService.current {
                service.handle(processingTask)
            } else {
                processingTask.setTaskCompleted(success: false)
            }
        }

        // 通知デリゲートを設定する
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    // Google Sign-In コールバック URL を処理する
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

// 通知タップ処理
extension AppDelegate: UNUserNotificationCenterDelegate {
    // フォアグラウンド中の通知表示設定
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
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
}
