package com.studiofreesia.wondaywall.workers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.studiofreesia.wondaywall.App
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// 次回スケジュールスロット到達時にアプリを起こし、WorkManager の scheduled work を投入する
class ScheduledGenerationAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != ACTION_SCHEDULED_GENERATION_ALARM &&
            action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED
        ) {
            return
        }

        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.Default).launch {
            try {
                val app = context.applicationContext as App
                when (action) {
                    ACTION_SCHEDULED_GENERATION_ALARM -> {
                        app.taskSchedulerService.enqueueScheduledGenerationDueNow()
                    }
                    Intent.ACTION_BOOT_COMPLETED,
                    Intent.ACTION_MY_PACKAGE_REPLACED,
                    -> {
                        app.taskSchedulerService.rescheduleAlarmAfterSystemEvent()
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "定時生成アラームの処理に失敗しました", e)
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        private const val TAG = "ScheduledGenerationAlarm"
        const val ACTION_SCHEDULED_GENERATION_ALARM =
            "com.studiofreesia.wondaywall.action.SCHEDULED_GENERATION_ALARM"
    }
}
