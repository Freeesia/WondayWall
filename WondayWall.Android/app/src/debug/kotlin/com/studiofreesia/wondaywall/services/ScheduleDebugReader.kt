package com.studiofreesia.wondaywall.services

data class ScheduleDebugSnapshot(
    val alarmRegistered: Boolean,
    val expectedNextAlarmTimeMillis: Long?,
    val loadedAtMillis: Long,
)

// Debug ビルド専用の定時スケジュール状態読み取り
class ScheduleDebugReader(private val taskSchedulerService: TaskSchedulerService) {
    suspend fun loadSnapshot(): ScheduleDebugSnapshot =
        ScheduleDebugSnapshot(
            alarmRegistered = taskSchedulerService.hasScheduledAlarmRegistered(),
            expectedNextAlarmTimeMillis = taskSchedulerService.getExpectedNextScheduledAlarmTimeMillis(),
            loadedAtMillis = System.currentTimeMillis(),
        )
}
