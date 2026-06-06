package com.studiofreesia.wondaywall.services

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Constraints
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.studiofreesia.wondaywall.models.GenerationPhase
import com.studiofreesia.wondaywall.models.GenerationProgress
import com.studiofreesia.wondaywall.models.GenerationTrigger
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.models.UpdateSchedule
import com.studiofreesia.wondaywall.workers.ScheduledGenerationAlarmReceiver
import com.studiofreesia.wondaywall.workers.GenerationWorker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.util.Calendar
import java.util.UUID

// バックグラウンド定期生成の登録・解除・スロット判定を担当するサービス
// 定時起点は AlarmManager、生成実行は WorkManager の即時 OneTimeWorkRequest を使う
class TaskSchedulerService(
    private val context: Context,
    private val appConfigService: AppConfigService,
    private val historyService: HistoryService,
) {
    companion object {
        private const val TAG = "TaskSchedulerService"
        // WorkManager のユニークワーク名
        const val WORK_NAME = "WondayWall.BackgroundGeneration"
        const val KEY_TRIGGER = "trigger"
        const val KEY_PROGRESS_PERCENT = "progress_percent"
        const val KEY_PROGRESS_MESSAGE = "progress_message"
        const val KEY_PROGRESS_PHASE = "progress_phase"
        const val KEY_PROGRESS_HISTORY_ID = "progress_history_id"
        const val KEY_RESULT_HISTORY_ID = "result_history_id"
        const val KEY_RESULT_STATUS = "result_status"
        private const val SCHEDULED_ALARM_REQUEST_CODE = 4001

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

        fun inputDataFor(trigger: GenerationTrigger): Data =
            Data.Builder()
                .putString(KEY_TRIGGER, trigger.name)
                .build()

        fun progressToData(progress: GenerationProgress): Data =
            Data.Builder()
                .putInt(KEY_PROGRESS_PERCENT, progress.percent)
                .putString(KEY_PROGRESS_MESSAGE, progress.message)
                .putString(KEY_PROGRESS_PHASE, progress.phase.name)
                .putString(KEY_PROGRESS_HISTORY_ID, progress.historyId)
                .putString(KEY_TRIGGER, progress.trigger.name)
                .build()

        fun progressFromData(data: Data): GenerationProgress? {
            val triggerName = data.getString(KEY_TRIGGER) ?: return null
            val phaseName = data.getString(KEY_PROGRESS_PHASE) ?: return null
            val trigger = runCatching { GenerationTrigger.valueOf(triggerName) }.getOrNull() ?: return null
            val phase = runCatching { GenerationPhase.valueOf(phaseName) }.getOrNull() ?: return null
            return GenerationProgress(
                percent = data.getInt(KEY_PROGRESS_PERCENT, 0),
                message = data.getString(KEY_PROGRESS_MESSAGE).orEmpty(),
                phase = phase,
                historyId = data.getString(KEY_PROGRESS_HISTORY_ID),
                trigger = trigger,
            )
        }

        fun resultToData(item: HistoryItem): Data =
            Data.Builder()
                .putString(KEY_RESULT_HISTORY_ID, item.id)
                .putString(KEY_RESULT_STATUS, item.status.name)
                .build()
    }

    // 手動生成を WorkManager Foreground Worker 経由で即時登録する
    suspend fun enqueueManualGeneration(): Boolean =
        enqueueImmediateGeneration(GenerationTrigger.Manual)

    // 手動生成を登録し、WorkManager の完了まで待って履歴を返す
    suspend fun enqueueManualGenerationAndWait(): HistoryItem? {
        if (isGenerationWorkRunning()) return null
        val workRequest = buildImmediateGenerationRequest(GenerationTrigger.Manual)
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            workRequest,
        )
        val workInfo = waitForWorkCompletion(workRequest.id) ?: return null
        val historyId = workInfo.outputData.getString(KEY_RESULT_HISTORY_ID) ?: return null
        return historyService.getHistoryItem(historyId)
    }

    // 起動時補完生成を WorkManager Foreground Worker 経由で即時登録する
    suspend fun enqueueStartupRecoveryGeneration(): Boolean =
        enqueueImmediateGeneration(GenerationTrigger.StartupRecovery)

    // 定時アラームから、未処理スロットの scheduled work を即時登録する
    suspend fun enqueueScheduledGenerationDueNow(): Boolean {
        val config = appConfigService.getConfig()
        if (!config.autoGenerationEnabled) {
            cancelScheduledAlarm()
            Log.i(TAG, "定時アラームを無視しました: autoGenerationEnabled=false")
            return false
        }
        if (isGenerationWorkRunning()) {
            Log.i(TAG, "定時アラームを保留しました: 生成中")
            scheduleNext(allowWhileRunning = true)
            return false
        }
        if (isCurrentSlotProcessed()) {
            Log.i(TAG, "定時アラームをスキップしました: 現在スロットは処理済み")
            scheduleNext()
            return false
        }

        val workRequest = buildImmediateGenerationRequest(GenerationTrigger.Scheduled)
        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            workRequest,
        )
        Log.i(TAG, "定時アラームから scheduled work を即時登録しました id=${workRequest.id}")
        scheduleNext(allowWhileRunning = true)
        return true
    }

    private suspend fun enqueueImmediateGeneration(trigger: GenerationTrigger): Boolean {
        if (isGenerationWorkRunning()) return false
        val workRequest = buildImmediateGenerationRequest(trigger)

        WorkManager.getInstance(context).enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            workRequest,
        )
        return true
    }

    private suspend fun buildImmediateGenerationRequest(trigger: GenerationTrigger) =
        OneTimeWorkRequestBuilder<GenerationWorker>()
            .setInputData(inputDataFor(trigger))
            .setConstraints(buildConstraints())
            .build()

    // 次回スケジュールスロットを計算して AlarmManager に登録する
    suspend fun scheduleNext(allowWhileRunning: Boolean = false) {
        val config = appConfigService.getConfig()
        if (!config.autoGenerationEnabled) {
            cancelScheduledAlarm()
            return
        }
        val isRunning = isGenerationWorkRunning()
        if (isRunning && !allowWhileRunning) return

        val now = System.currentTimeMillis()
        val nextSlotMs = getNextScheduledSlotAfter(now, config.schedule)
        scheduleScheduledAlarm(nextSlotMs)
        Log.i(TAG, "次回定時生成アラームを登録しました nextSlotMs=$nextSlotMs")
    }

    // 自動生成を無効化し、登録済みの WorkManager タスクをキャンセルする
    fun cancelScheduled() {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        cancelScheduledAlarm()
        Log.i(TAG, "定時生成をキャンセルしました")
    }

    // 旧実装で残った WorkManager の delayed 予約を消し、AlarmManager だけに張り直す
    suspend fun rescheduleAlarmAfterSystemEvent() {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        Log.i(TAG, "旧 WorkManager 定時予約をキャンセルしました")
        scheduleNext()
    }

    // WorkManager のユニークワークが実行中か確認する
    suspend fun isGenerationWorkRunning(): Boolean =
        getWorkInfos().any { it.state == WorkInfo.State.RUNNING }

    // AlarmManager の次回予約が存在するか確認する
    suspend fun hasScheduledWork(): Boolean =
        hasScheduledAlarm()

    // AlarmManager の次回予約が存在するか確認する（デバッグ表示用）
    suspend fun hasScheduledAlarmRegistered(): Boolean =
        hasScheduledAlarm()

    // 現在の設定から次回スケジュールスロットを計算する（デバッグ表示用）
    suspend fun getExpectedNextScheduledAlarmTimeMillis(): Long? {
        val config = appConfigService.getConfig()
        if (!config.autoGenerationEnabled) return null
        return getNextScheduledSlotAfter(System.currentTimeMillis(), config.schedule)
    }

    // 現在時刻に対応するスケジュールスロット開始時刻を返す（ウィジェット表示用）
    suspend fun getCurrentSlotStartedAtMillis(): Long {
        val config = appConfigService.getConfig()
        return getLatestScheduledSlotAtOrBefore(System.currentTimeMillis(), config.schedule)
    }

    // 現在設定に基づく次回スケジュールスロット開始時刻を返す（ウィジェット表示用）
    suspend fun getNextSlotStartedAtMillis(): Long {
        val config = appConfigService.getConfig()
        return getNextScheduledSlotAfter(System.currentTimeMillis(), config.schedule)
    }

    // 実行中 Work の最新 progress を取得する
    suspend fun getCurrentProgress(): GenerationProgress? =
        getWorkInfos()
            .firstOrNull { it.state == WorkInfo.State.RUNNING }
            ?.progress
            ?.let(::progressFromData)

    // 起動時・復帰時に現在スケジュール枠が未実行か確認する
    suspend fun isScheduledGenerationNeeded(): Boolean {
        val config = appConfigService.getConfig()
        if (!config.autoGenerationEnabled) return false
        if (config.generateOnlyOnWifi && !isWifiConnected()) return false
        return !isCurrentSlotProcessed()
    }

    // 現在のスケジュールスロットがすでに処理済みかを確認する
    suspend fun isCurrentSlotProcessed(): Boolean {
        val config = appConfigService.getConfig()
        val now = System.currentTimeMillis()
        val latestSlotMs = getLatestScheduledSlotAtOrBefore(now, config.schedule)
        val lastCompletedMs = historyService.getLastCompletedRunTimeMillis() ?: return false
        return lastCompletedMs >= latestSlotMs
    }

    private fun scheduleScheduledAlarm(nextSlotMs: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = scheduledAlarmPendingIntent(PendingIntent.FLAG_UPDATE_CURRENT) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextSlotMs, pendingIntent)
        } else {
            alarmManager.set(AlarmManager.RTC_WAKEUP, nextSlotMs, pendingIntent)
        }
    }

    private fun cancelScheduledAlarm() {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pendingIntent = scheduledAlarmPendingIntent(PendingIntent.FLAG_NO_CREATE) ?: return
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private fun hasScheduledAlarm(): Boolean =
        scheduledAlarmPendingIntent(PendingIntent.FLAG_NO_CREATE) != null

    private fun scheduledAlarmPendingIntent(flags: Int): PendingIntent? {
        val intent = Intent(context, ScheduledGenerationAlarmReceiver::class.java).apply {
            action = ScheduledGenerationAlarmReceiver.ACTION_SCHEDULED_GENERATION_ALARM
            setPackage(context.packageName)
        }
        return PendingIntent.getBroadcast(
            context,
            SCHEDULED_ALARM_REQUEST_CODE,
            intent,
            flags or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private suspend fun getWorkInfos(): List<WorkInfo> = withContext(Dispatchers.IO) {
        try {
            WorkManager.getInstance(context).getWorkInfosForUniqueWork(WORK_NAME).get()
        } catch (_: Exception) {
            emptyList()
        }
    }

    private suspend fun buildConstraints(): Constraints {
        val config = appConfigService.getConfig()
        return Constraints.Builder()
            .apply {
                if (config.generateOnlyOnWifi) {
                    setRequiredNetworkType(NetworkType.UNMETERED)
                } else {
                    setRequiredNetworkType(NetworkType.CONNECTED)
                }
                setRequiresBatteryNotLow(config.skipOnBatterySaver)
            }
            .build()
    }

    private suspend fun waitForWorkCompletion(id: UUID): WorkInfo? {
        while (true) {
            val workInfo = getWorkInfo(id) ?: return null
            if (workInfo.state == WorkInfo.State.SUCCEEDED ||
                workInfo.state == WorkInfo.State.FAILED ||
                workInfo.state == WorkInfo.State.CANCELLED
            ) {
                return workInfo
            }
            delay(1_000)
        }
    }

    private suspend fun getWorkInfo(id: UUID): WorkInfo? = withContext(Dispatchers.IO) {
        try {
            WorkManager.getInstance(context).getWorkInfoById(id).get()
        } catch (_: Exception) {
            null
        }
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
            // 今日の対象スロットがまだ先なら今日を返す
            for (i in 0..14) {
                val cal = calendarAtStartOfDay(nowMs).apply {
                    add(Calendar.DAY_OF_YEAR, i)
                    set(Calendar.HOUR_OF_DAY, FIRST_DAILY_SLOT_HOUR)
                    set(Calendar.MINUTE, 0)
                    set(Calendar.SECOND, 0)
                    set(Calendar.MILLISECOND, 0)
                }
                if (cal.timeInMillis > nowMs && weekDays.contains(cal.get(Calendar.DAY_OF_WEEK))) {
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

    // Wi-Fi 接続中か確認する
    private fun isWifiConnected(): Boolean {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as android.net.ConnectivityManager
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)
    }

}
