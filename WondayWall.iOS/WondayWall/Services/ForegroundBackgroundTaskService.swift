import Foundation
import BackgroundTasks
import OSLog

// 手動生成・起動時生成中にアプリがバックグラウンドへ移った場合の継続を管理するサービス
// BGContinuedProcessingTask を使い、ユーザーに進捗を明示しながら処理を継続する
final class ForegroundBackgroundTaskService {
    private let logger = Logger(subsystem: "com.studiofreesia.wondaywall", category: "ForegroundBackgroundTaskService")

    // BGContinuedProcessingTask の登録識別子（Info.plist では wildcard 形式で登録する）
    static var continuedTaskIdentifier: String {
        "\(Bundle.main.bundleIdentifier ?? "com.studiofreesia.wondaywall").manual.*"
    }

    static func cancelPendingRequest() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: continuedTaskIdentifier)
    }

    // AppDelegate のハンドラーから参照できるよう静的に保持する
    static weak var current: ForegroundBackgroundTaskService?

    private var onExpiration: (() -> Void)?
    private var completionObserver: NSObjectProtocol?
    private var progressObserver: NSObjectProtocol?
    // weak ではなく strong で保持する。weak にするとシステムがタスクオブジェクトへの参照を
    // 手放した時点で activeTask が nil になり、app の BG 保護が失われる。
    private var activeTask: BGContinuedProcessingTask?
    private var isTaskCompleted = false
    private var submittedRequestIdentifier: String?

    init() {
        ForegroundBackgroundTaskService.current = self
    }

    // フォアグラウンド開始の生成を BGContinuedProcessingTask 経由で開始する
    func beginTask(onExpiration: @escaping () -> Void) {
        self.onExpiration = onExpiration
        let requestIdentifier = Self.continuedTaskIdentifier
        submittedRequestIdentifier = requestIdentifier
        logger.notice("beginTask: BGContinuedProcessingTaskRequest を submit 試行 (identifier=\(requestIdentifier, privacy: .public))")
        let request = BGContinuedProcessingTaskRequest(
            identifier: requestIdentifier,
            title: "壁紙を生成中",
            subtitle: "壁紙候補画像を作成しています"
        )
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.notice("beginTask: submit 成功 strategy=fail")
            notifyContinuationStatus(isAvailable: true)
        } catch {
            // submit 失敗は生成自体の失敗にはしないが、BG継続保護は効かないため詳細を残す。
            let nsError = error as NSError
            logger.error("beginTask: submit 失敗 domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) message=\(error.localizedDescription, privacy: .public)")
            notifyContinuationStatus(
                isAvailable: false,
                message: Self.warningMessage(for: nsError)
            )
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
                if let identifier = self.submittedRequestIdentifier {
                    self.logger.notice("FG完了: BGContinuedProcessingTask リクエストをキャンセル (identifier=\(identifier, privacy: .public))")
                    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
                }
                self.onExpiration = nil
                self.submittedRequestIdentifier = nil
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
        submittedRequestIdentifier = nil
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

    private static func warningMessage(for error: NSError) -> String {
        if error.domain == BGTaskScheduler.errorDomain,
           let code = BGTaskScheduler.Error.Code(rawValue: error.code) {
            switch code {
            case .unavailable:
                return "この環境ではバックグラウンド継続を開始できません。生成が完了するまでアプリを開いたままにしてください。"
            case .notPermitted:
                return "バックグラウンド継続が許可されていません。生成が完了するまでアプリを開いたままにしてください。"
            case .immediateRunIneligible:
                return "現在の端末状況ではバックグラウンド継続をすぐ開始できません。生成が完了するまでアプリを開いたままにしてください。"
            default:
                break
            }
        }
        return "バックグラウンド継続を開始できませんでした。生成が完了するまでアプリを開いたままにしてください。"
    }

    private func notifyContinuationStatus(isAvailable: Bool, message: String? = nil) {
        DispatchQueue.main.async {
            var userInfo: [String: Any] = ["isAvailable": isAvailable]
            if let message {
                userInfo["message"] = message
            }
            NotificationCenter.default.post(
                name: .generationContinuationStatusChanged,
                object: nil,
                userInfo: userInfo
            )
        }
    }
}
