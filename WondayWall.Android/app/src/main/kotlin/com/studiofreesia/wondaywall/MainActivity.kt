package com.studiofreesia.wondaywall

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.studiofreesia.wondaywall.models.GenerationProgress
import com.studiofreesia.wondaywall.ui.navigation.AppNavigation
import com.studiofreesia.wondaywall.ui.theme.WondayWallTheme
import kotlinx.coroutines.launch

private enum class StartupAlertMode {
    AlreadyGenerating,
    ResumeGeneration,
    ConfirmStart,
}

private data class StartupAlertState(
    val mode: StartupAlertMode,
    val message: String,
)

// アプリのメインアクティビティ
class MainActivity : ComponentActivity() {

    private var startupAlert by mutableStateOf<StartupAlertState?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WondayWallTheme {
                val app = application as App
                AppNavigation(
                    appConfigService = app.appConfigService,
                    generationCoordinator = app.generationCoordinator,
                    historyService = app.historyService,
                    wallpaperService = app.wallpaperService,
                    contextService = app.contextService,
                    taskSchedulerService = app.taskSchedulerService,
                )
                startupAlert?.let { alert ->
                    StartupGenerationAlert(
                        alert = alert,
                        onDismiss = { handleStartupAlertDismiss(alert.mode) },
                        onConfirm = { handleStartupAlertConfirm(alert.mode) },
                    )
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch {
            evaluateStartupGeneration()
        }
    }

    private suspend fun evaluateStartupGeneration() {
        if (startupAlert != null) return
        val app = application as App
        val config = app.appConfigService.getConfig()
        if (config.googleAiApiKey.isBlank()) return

        val progress = app.generationCoordinator.progress.value
            ?: app.taskSchedulerService.getCurrentProgress()
        if (app.generationCoordinator.isGenerating.value || app.taskSchedulerService.isGenerationWorkRunning()) {
            startupAlert = StartupAlertState(
                mode = StartupAlertMode.AlreadyGenerating,
                message = progress.runningMessage(),
            )
            return
        }

        val resumable = app.historyService.getGeneratingWithPrompt()
            ?: app.historyService.getPendingGeneratingItem()
        if (resumable != null) {
            startupAlert = StartupAlertState(
                mode = StartupAlertMode.ResumeGeneration,
                message = "中断された生成があります。保存済みの状態から再開しますか？",
            )
            return
        }

        if (app.taskSchedulerService.isScheduledGenerationNeeded()) {
            startupAlert = StartupAlertState(
                mode = StartupAlertMode.ConfirmStart,
                message = "前回のスケジュール枠がまだ未実行です。今すぐ生成を行いますか？",
            )
            return
        }

        if (config.autoGenerationEnabled && !app.taskSchedulerService.hasScheduledWork()) {
            app.taskSchedulerService.scheduleNext()
        }
    }

    private fun handleStartupAlertDismiss(mode: StartupAlertMode) {
        startupAlert = null
        if (mode == StartupAlertMode.ConfirmStart || mode == StartupAlertMode.ResumeGeneration) {
            lifecycleScope.launch {
                (application as App).taskSchedulerService.scheduleNext()
            }
        }
    }

    private fun handleStartupAlertConfirm(mode: StartupAlertMode) {
        startupAlert = null
        if (mode == StartupAlertMode.ResumeGeneration || mode == StartupAlertMode.ConfirmStart) {
            lifecycleScope.launch {
                (application as App).taskSchedulerService.enqueueStartupRecoveryGeneration()
            }
        }
    }

    private fun GenerationProgress?.runningMessage(): String =
        this?.let { "壁紙を生成中です。完了までお待ちください。（進捗: ${it.percent}% ${it.message}）" }
            ?: "壁紙を生成中です。完了までお待ちください。"
}

@Composable
private fun StartupGenerationAlert(
    alert: StartupAlertState,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                when (alert.mode) {
                    StartupAlertMode.AlreadyGenerating -> "壁紙を生成しています"
                    StartupAlertMode.ResumeGeneration -> "生成を再開できます"
                    StartupAlertMode.ConfirmStart -> "起動時の壁紙生成"
                }
            )
        },
        text = { Text(alert.message) },
        confirmButton = {
            when (alert.mode) {
                StartupAlertMode.AlreadyGenerating -> {
                    TextButton(onClick = onDismiss) { Text("閉じる") }
                }
                StartupAlertMode.ResumeGeneration -> {
                    TextButton(onClick = onConfirm) { Text("再開") }
                }
                StartupAlertMode.ConfirmStart -> {
                    TextButton(onClick = onConfirm) { Text("今すぐ生成") }
                }
            }
        },
        dismissButton = {
            if (alert.mode != StartupAlertMode.AlreadyGenerating) {
                TextButton(onClick = onDismiss) { Text("あとで") }
            }
        },
    )
}
