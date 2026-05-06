import Foundation
import UserNotifications

// ローカル通知を担当するサービス
final class NotificationService {
    // 通知権限を要求する（すでに許可済みなら即返す）
    @discardableResult
    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        default:
            return false
        }
    }

    // 生成完了通知をスケジュールする
    func scheduleSuccessNotification(imagePath: String?) async {
        guard await requestPermission() else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "壁紙を生成しました"
        content.body = "新しい壁紙候補が生成されました。タップして確認してください。"
        content.sound = .default
        content.userInfo = ["type": "generation.success", "imagePath": imagePath ?? ""]
        // 画像を通知に添付する
        if let path = imagePath,
            let attachment = try? UNNotificationAttachment(
                identifier: UUID().uuidString,
                url: URL(fileURLWithPath: path),
                options: nil
            )
        {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(
            identifier: "generation.success.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // 生成失敗通知をスケジュールする
    func scheduleFailureNotification(error: String) async {
        guard await requestPermission() else { return }
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "壁紙生成に失敗しました"
        content.body = error
        content.sound = .defaultCritical
        content.userInfo = ["type": "generation.failure"]
        let request = UNNotificationRequest(
            identifier: "generation.failure.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
