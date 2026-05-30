package com.studiofreesia.wondaywall.workers

import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.studiofreesia.wondaywall.App
import com.studiofreesia.wondaywall.models.GenerationPhase
import com.studiofreesia.wondaywall.models.GenerationProgress
import com.studiofreesia.wondaywall.models.GenerationTrigger
import com.studiofreesia.wondaywall.services.NotificationHelper
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

// 手動生成・定期生成・起動時補完を実行する WorkManager Worker
class GenerationWorker(
    appContext: Context,
    workerParams: WorkerParameters,
) : CoroutineWorker(appContext, workerParams) {
    companion object {
        private const val TAG = "GenerationWorker"
    }

    override suspend fun doWork(): Result {
        val trigger = inputData.getString(TaskSchedulerService.KEY_TRIGGER)
            ?.let { runCatching { GenerationTrigger.valueOf(it) }.getOrNull() }
            ?: GenerationTrigger.Scheduled
        val app = applicationContext as App
        val initialProgress = GenerationProgress(
            percent = 0,
            message = "生成を開始しています",
            phase = GenerationPhase.Queued,
            trigger = trigger,
        )
        return try {
            Log.i(TAG, "生成 Worker を開始します trigger=$trigger id=$id")
            setProgress(TaskSchedulerService.progressToData(initialProgress))
            var foregroundUpdatesEnabled = trigger != GenerationTrigger.Scheduled
            if (foregroundUpdatesEnabled) {
                // 手動・起動時補完は通知付き Foreground Worker として開始を試みる。
                foregroundUpdatesEnabled = setForegroundIfAllowed(initialProgress)
            }

            val historyItem = coroutineScope {
                val progressJob = launch {
                    app.generationCoordinator.progress.collect { progress ->
                        if (progress == null) return@collect
                        val data = TaskSchedulerService.progressToData(progress)
                        setProgress(data)
                        if (foregroundUpdatesEnabled) {
                            foregroundUpdatesEnabled = setForegroundIfAllowed(progress)
                        }
                    }
                }

                try {
                    app.generationCoordinator.runForWorker(trigger)
                } finally {
                    progressJob.cancel()
                    app.taskSchedulerService.scheduleNext(allowWhileRunning = true)
                }
            }
            Log.i(TAG, "生成 Worker が完了しました trigger=$trigger status=${historyItem.status} id=$id")
            Result.success(TaskSchedulerService.resultToData(historyItem))
        } catch (e: Exception) {
            // 失敗時はリトライしない（次回スロットで再試行する）
            Log.e(TAG, "生成 Worker に失敗しました", e)
            app.taskSchedulerService.scheduleNext(allowWhileRunning = true)
            Result.failure()
        }
    }

    private suspend fun setForegroundIfAllowed(progress: GenerationProgress): Boolean =
        try {
            setForeground(createForegroundInfo(progress))
            true
        } catch (e: Exception) {
            Log.w(TAG, "Foreground Worker 通知の設定に失敗したため通常 Worker として継続します", e)
            false
        }

    // フォアグラウンドサービス用の通知情報を作成する
    private fun createForegroundInfo(progress: GenerationProgress? = null): ForegroundInfo {
        val app = applicationContext as App
        val notification = app.notificationHelper.buildProgressNotification(progress)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ForegroundInfo(
                NotificationHelper.NOTIFICATION_ID_PROGRESS,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            ForegroundInfo(NotificationHelper.NOTIFICATION_ID_PROGRESS, notification)
        }
    }
}
