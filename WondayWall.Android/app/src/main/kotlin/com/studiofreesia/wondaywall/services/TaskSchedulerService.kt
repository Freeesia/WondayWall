package com.studiofreesia.wondaywall.services

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.studiofreesia.wondaywall.models.UpdateSchedule
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

        // すべてのスケジュールで1日の最初の更新は4:00に揃える（Windows版 ScheduleHelper.FirstDailySlot と同じ）
        private const val FIRST_DAILY_SLOT_HOUR = 4

        // 週次スケジュールの対象曜日定義（Windows版 ScheduleHelper と同じ）
        private val ONCE_A_WEEK_DAYS = setOf(Calendar.MONDAY)
        private val TWICE_A_WEEK_DAYS = setOf(Calendar.MONDAY, Calendar.THURSDAY)
        private val THREE_TIMES_A_WEEK_DAYS = setOf(Calendar.MONDAY, Calendar.WEDNESDAY, Calendar.FRIDAY)

        // 1日複数回スケジュールのスロット時刻（時:分）（Windows版 ScheduleHelper と同じ）
        private val ONCE_A_DAY_SLOTS = listOf(FIRST_DAILY_SLOT_HOUR * 60)         // 4:00
        private val THREE_TIMES_A_DAY_SLOTS = listOf(
            FIRST_DAILY_SLOT_HOUR * 60,   // 4:00（朝）
            12 * 60,                       // 12:00（昼）
            18 * 60,                       // 18:00（晩）
        )
    }

    // 次回スケジュールスロットを計算して WorkManager に登録する
    suspend fun scheduleNext() {
        val config = appConfigService.getConfig()
        if (!config.autoGenerationEnabled) return

        val now = System.currentTimeMillis()
        val nextSlotMs = getNextScheduledSlotAfter(now, config.schedule)
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
        val latestSlotMs = getLatestScheduledSlotAtOrBefore(now, config.schedule)
        val lastSuccessMs = historyService.getLastSuccessTimeMillis() ?: return false
        return lastSuccessMs >= latestSlotMs
    }

    // 現在時刻以前の最新スケジュールスロットを返す（エポックミリ秒）
    private fun getLatestScheduledSlotAtOrBefore(nowMs: Long, schedule: UpdateSchedule): Long {
        if (isWeeklySchedule(schedule)) {
            val weekDays = getWeekDays(schedule)
            // 過去7日間を逆順に走査して直近の対象日を探す
            for (i in 0 until 7) {
                val cal = calendarAtStartOfDay(nowMs).apply { add(Calendar.DAY_OF_YEAR, -i) }
                cal.set(Calendar.HOUR_OF_DAY, FIRST_DAILY_SLOT_HOUR)
                cal.set(Calendar.MINUTE, 0)
                cal.set(Calendar.SECOND, 0)
                cal.set(Calendar.MILLISECOND, 0)
                if (cal.timeInMillis <= nowMs && weekDays.contains(cal.get(Calendar.DAY_OF_WEEK))) {
                    return cal.timeInMillis
                }
            }
            // フォールバック（通常は到達しない）
            return calendarAtStartOfDay(nowMs).apply {
                add(Calendar.DAY_OF_YEAR, -7)
                set(Calendar.HOUR_OF_DAY, FIRST_DAILY_SLOT_HOUR)
            }.timeInMillis
        } else {
            val slotMinutes = getDailySlotMinutes(schedule)
            val midnightMs = getMidnightMillis(nowMs)

            // 当日のスロットを逆順に探す
            for (slotMin in slotMinutes.reversed()) {
                val slotMs = midnightMs + slotMin * 60_000L
                if (slotMs <= nowMs) return slotMs
            }
            // 当日に該当スロットがなければ前日の最終スロットを返す
            val prevMidnightMs = midnightMs - 24 * 60 * 60_000L
            return prevMidnightMs + slotMinutes.last() * 60_000L
        }
    }

    // 現在時刻の次のスケジュールスロットを返す（エポックミリ秒）
    private fun getNextScheduledSlotAfter(nowMs: Long, schedule: UpdateSchedule): Long {
        if (isWeeklySchedule(schedule)) {
            val weekDays = getWeekDays(schedule)
            // 最大14日先まで走査して次の対象日を探す
            for (i in 1..14) {
                val cal = calendarAtStartOfDay(nowMs).apply {
                    add(Calendar.DAY_OF_YEAR, i)
                    set(Calendar.HOUR_OF_DAY, FIRST_DAILY_SLOT_HOUR)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                if (weekDays.contains(cal.get(Calendar.DAY_OF_WEEK))) {
                    return cal.timeInMillis
                }
            }
            // フォールバック（通常は到達しない）
            return nowMs + 7 * 24 * 60 * 60_000L
        } else {
            val slotMinutes = getDailySlotMinutes(schedule)
            val midnightMs = getMidnightMillis(nowMs)

            // 当日の残りスロットを順に探す
            for (slotMin in slotMinutes) {
                val slotMs = midnightMs + slotMin * 60_000L
                if (slotMs > nowMs) return slotMs
            }
            // 翌日の最初のスロット
            return midnightMs + 24 * 60 * 60_000L + slotMinutes.first() * 60_000L
        }
    }

    // 週次スケジュールかどうかを返す
    private fun isWeeklySchedule(schedule: UpdateSchedule): Boolean =
        schedule == UpdateSchedule.OnceAWeek ||
            schedule == UpdateSchedule.TwiceAWeek ||
            schedule == UpdateSchedule.ThreeTimesAWeek

    // 週次スケジュールの対象曜日セット（Calendar.DAY_OF_WEEK 値）を返す
    private fun getWeekDays(schedule: UpdateSchedule): Set<Int> = when (schedule) {
        UpdateSchedule.OnceAWeek -> ONCE_A_WEEK_DAYS
        UpdateSchedule.TwiceAWeek -> TWICE_A_WEEK_DAYS
        UpdateSchedule.ThreeTimesAWeek -> THREE_TIMES_A_WEEK_DAYS
        else -> emptySet()
    }

    // 日次スケジュールの1日内スロット時刻（分）一覧を返す
    private fun getDailySlotMinutes(schedule: UpdateSchedule): List<Int> = when (schedule) {
        UpdateSchedule.ThreeTimesADay -> THREE_TIMES_A_DAY_SLOTS
        else -> ONCE_A_DAY_SLOTS
    }

    // 指定エポックミリ秒の当日0時（ローカルタイム）の Calendar を返す
    private fun calendarAtStartOfDay(epochMs: Long): Calendar =
        Calendar.getInstance().apply {
            timeInMillis = epochMs
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

    // 指定エポックミリ秒の当日0時（ローカルタイム）をエポックミリ秒で返す
    private fun getMidnightMillis(epochMs: Long): Long = calendarAtStartOfDay(epochMs).timeInMillis
}
