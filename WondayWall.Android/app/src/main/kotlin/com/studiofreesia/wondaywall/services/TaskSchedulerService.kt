package com.studiofreesia.wondaywall.services

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.studiofreesia.wondaywall.workers.GenerationWorker
import java.util.Calendar
import java.util.concurrent.TimeUnit

// バックグラウンド定期生成の登録・解除・スロット判定を担当するサービス
// 内部では WorkManager の OneTimeWorkRequest を使う
class TaskSchedulerService(
    private val context: Context,
    private val appConfigService: AppConfigService,
    private val historyService: HistoryService,
) {
    companion object {
        // WorkManager のユニークワーク名
        const val WORK_NAME = "WondayWall.BackgroundGeneration"
    }

    // 次回スケジュールスロットを計算して WorkManager に登録する
    suspend fun scheduleNext() {
        val config = appConfigService.getConfig()
        if (!config.autoGenerationEnabled) return

        val now = System.currentTimeMillis()
        val nextSlotMs = getNextScheduledSlotAfter(now, config.runsPerDay)
        val delayMs = (nextSlotMs - now).coerceAtLeast(0L)

        val constraints = Constraints.Builder()
            .apply {
                if (config.generateOnlyOnWifi) {
                    setRequiredNetworkType(NetworkType.UNMETERED)
                } else {
                    setRequiredNetworkType(NetworkType.CONNECTED)
                }
            }
            .build()

        val workRequest = OneTimeWorkRequestBuilder<GenerationWorker>()
            .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
            .setConstraints(constraints)
            .build()

        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            workRequest,
        )
    }

    // 自動生成を無効化し、登録済みの WorkManager タスクをキャンセルする
    fun cancelScheduled() {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    // 現在のスケジュールスロットがすでに処理済みかを確認する
    suspend fun isCurrentSlotProcessed(): Boolean {
        val config = appConfigService.getConfig()
        val now = System.currentTimeMillis()
        val latestSlotMs = getLatestScheduledSlotAtOrBefore(now, config.runsPerDay)
        val lastSuccessMs = historyService.getLastSuccessTimeMillis() ?: return false
        return lastSuccessMs >= latestSlotMs
    }

    // RunsPerDay から当日のスロット間隔（ミリ秒）を計算する
    private fun slotIntervalMs(runsPerDay: Int): Long {
        val validRunsPerDay = runsPerDay.coerceIn(1, 24)
        return (24L * 60 * 60 * 1000) / validRunsPerDay
    }

    // 現在時刻以前の最新スケジュールスロットを取得する（エポックミリ秒）
    private fun getLatestScheduledSlotAtOrBefore(nowMs: Long, runsPerDay: Int): Long {
        val intervalMs = slotIntervalMs(runsPerDay)
        // 当日0時を起点にスロットを計算する
        val midnightMs = getMidnightMillis(nowMs)
        val elapsed = nowMs - midnightMs
        val slotIndex = elapsed / intervalMs
        return midnightMs + slotIndex * intervalMs
    }

    // 現在時刻の次のスケジュールスロットを取得する（エポックミリ秒）
    private fun getNextScheduledSlotAfter(nowMs: Long, runsPerDay: Int): Long {
        val latestSlot = getLatestScheduledSlotAtOrBefore(nowMs, runsPerDay)
        val intervalMs = slotIntervalMs(runsPerDay)
        return latestSlot + intervalMs
    }

    // 指定エポックミリ秒の当日0時（ローカルタイム）をエポックミリ秒で返す
    private fun getMidnightMillis(epochMs: Long): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = epochMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return cal.timeInMillis
    }
}
