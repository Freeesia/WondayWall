package com.studiofreesia.wondaywall.services

import android.content.Context
import android.os.Build
import androidx.work.WorkInfo
import androidx.work.WorkManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class WorkManagerDebugSnapshot(
    val workName: String,
    val workInfos: List<WorkInfoDebugItem>,
    val loadedAtMillis: Long,
)

data class WorkInfoDebugItem(
    val id: String,
    val state: String,
    val nextScheduleTimeMillis: Long,
    val initialDelayMillis: Long,
    val runAttemptCount: Int,
    val stopReason: String,
    val requiredNetworkType: String,
    val tags: List<String>,
)

// Debug ビルド専用の WorkManager 状態読み取り
class WorkManagerDebugReader(private val context: Context) {
    suspend fun loadSnapshot(): WorkManagerDebugSnapshot = withContext(Dispatchers.IO) {
        val workInfos = runCatching {
            WorkManager.getInstance(context)
                .getWorkInfosForUniqueWork(TaskSchedulerService.WORK_NAME)
                .get()
        }.getOrDefault(emptyList())

        WorkManagerDebugSnapshot(
            workName = TaskSchedulerService.WORK_NAME,
            workInfos = workInfos.map { it.toDebugItem() },
            loadedAtMillis = System.currentTimeMillis(),
        )
    }

    private fun WorkInfo.toDebugItem(): WorkInfoDebugItem =
        WorkInfoDebugItem(
            id = id.toString(),
            state = state.name,
            nextScheduleTimeMillis = nextScheduleTimeMillis,
            initialDelayMillis = initialDelayMillis,
            runAttemptCount = runAttemptCount,
            stopReason = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                stopReason.toString()
            } else {
                "-"
            },
            requiredNetworkType = constraints.requiredNetworkType.name,
            tags = tags.sorted(),
        )
}
