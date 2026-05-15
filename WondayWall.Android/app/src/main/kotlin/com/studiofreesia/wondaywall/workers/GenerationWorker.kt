package com.studiofreesia.wondaywall.workers

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.studiofreesia.wondaywall.App
import com.studiofreesia.wondaywall.services.NotificationHelper

// バックグラウンド定期生成を実行する WorkManager ワーカー
class GenerationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        return try {
            // フォアグラウンド通知を表示して OS による中断を防ぐ
            setForeground(createForegroundInfo())

            val app = applicationContext as App
            // スケジュール生成を実行する（スロット判定・スキップ判定を含む）
            app.generationCoordinator.runScheduledAsync()

            Result.success()
        } catch (e: Exception) {
            // 失敗時はリトライしない（次回スロットで再試行する）
            Result.failure()
        }
    }

    // フォアグラウンドサービス用の通知情報を作成する
    private fun createForegroundInfo(): ForegroundInfo {
        val app = applicationContext as App
        val notification = app.notificationHelper.buildProgressNotification()
        return ForegroundInfo(NotificationHelper.NOTIFICATION_ID_PROGRESS, notification)
    }
}
