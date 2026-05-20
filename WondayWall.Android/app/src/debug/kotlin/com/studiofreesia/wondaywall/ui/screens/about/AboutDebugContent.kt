package com.studiofreesia.wondaywall.ui.screens.about

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.DebugConfig
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.DummyAiService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.AiService
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import com.studiofreesia.wondaywall.services.WorkManagerDebugReader
import com.studiofreesia.wondaywall.services.WorkManagerDebugSnapshot
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.launch

@Composable
internal fun AboutDebugEntry(onShowDebugInfo: () -> Unit) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        TextButton(
            onClick = onShowDebugInfo,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 4.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.Default.BugReport,
                    contentDescription = null,
                    modifier = Modifier.size(28.dp),
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    "デバッグ情報",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
                Icon(
                    Icons.Default.ChevronRight,
                    contentDescription = null,
                    modifier = Modifier.size(16.dp),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
internal fun AboutDebugScreen(
    appConfigService: AppConfigService,
    generationCoordinator: GenerationCoordinator,
    aiService: AiService,
    taskSchedulerService: TaskSchedulerService,
    onBack: () -> Unit,
    onClose: () -> Unit,
) {
    val appContext = LocalContext.current.applicationContext
    val workManagerDebugReader = remember(appContext) { WorkManagerDebugReader(appContext) }
    val isGenerating by generationCoordinator.isGenerating.collectAsState()
    val generationProgress by generationCoordinator.progress.collectAsState()
    val scope = rememberCoroutineScope()
    var config by remember { mutableStateOf<AppConfig?>(null) }
    var debugConfig by remember { mutableStateOf(DebugConfig()) }
    var workSnapshot by remember { mutableStateOf<WorkManagerDebugSnapshot?>(null) }
    var loadedAt by remember { mutableLongStateOf(0L) }

    fun reload() {
        scope.launch {
            val loadedConfig = appConfigService.getConfig()
            config = loadedConfig
            debugConfig = loadedConfig.debugConfig
            workSnapshot = workManagerDebugReader.loadSnapshot()
            loadedAt = System.currentTimeMillis()
        }
    }

    fun updateDebugConfig(update: (DebugConfig) -> DebugConfig) {
        scope.launch {
            val updated = update(debugConfig).normalized()
            appConfigService.updateConfig { it.copy(debugConfig = updated) }
            debugConfig = updated
            config = appConfigService.getConfig()
        }
    }

    LaunchedEffect(Unit) {
        reload()
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
            }
            Text(
                "デバッグ情報",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { reload() }) {
                Text("更新")
            }
            TextButton(onClick = onClose) {
                Text("閉じる")
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("デバッグ設定", style = MaterialTheme.typography.titleMedium)
                DebugSwitchRow(
                    label = "ダミーAIサービスを使う",
                    checked = debugConfig.useDummyAiService,
                    onCheckedChange = {
                        updateDebugConfig { config ->
                            config.copy(useDummyAiService = it)
                        }
                    },
                )
                Text(
                    "切り替えは次回アプリ起動時に反映されます。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    "遅延設定は次のダミー生成から反映されます。",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                DebugDelayRow(
                    label = "プロンプト生成遅延",
                    value = debugConfig.dummyPromptDelaySeconds,
                    onValueChange = { value ->
                        updateDebugConfig { config ->
                            config.copy(dummyPromptDelaySeconds = value)
                        }
                    },
                )
                DebugDelayRow(
                    label = "画像生成遅延",
                    value = debugConfig.dummyImageDelaySeconds,
                    onValueChange = { value ->
                        updateDebugConfig { config ->
                            config.copy(dummyImageDelaySeconds = value)
                        }
                    },
                )
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("アプリ状態", style = MaterialTheme.typography.titleMedium)
                DebugInfoRow("ビルド種別", "Debug")
                DebugInfoRow("AI サービス", if (aiService is DummyAiService) "Dummy" else "Live")
                DebugInfoRow("次回起動時のAIサービス", if (debugConfig.useDummyAiService) "Dummy" else "Live")
                DebugInfoRow("生成中", if (isGenerating) "YES" else "NO")
                DebugInfoRow("進捗", generationProgress?.let { "${it.percent}% ${it.message}" } ?: "-")
                DebugInfoRow("フェーズ", generationProgress?.phase?.name ?: "-")
                DebugInfoRow("トリガー", generationProgress?.trigger?.name ?: "-")
                DebugInfoRow("履歴ID", generationProgress?.historyId ?: "-")
                DebugInfoRow("自動生成", if (config?.autoGenerationEnabled == true) "ON" else "OFF")
                DebugInfoRow("API キー", if (config?.googleAiApiKey?.isNotBlank() == true) "設定済み" else "未設定")
                DebugInfoRow("スケジュール", config?.schedule?.displayName() ?: "-")
                DebugInfoRow("対象カレンダー", "${config?.targetCalendarIds?.size ?: 0} 件")
                DebugInfoRow("RSS ソース", "${config?.rssSources?.size ?: 0} 件")
                DebugInfoRow("最終取得", if (loadedAt > 0) formatDebugTime(loadedAt) else "-")
            }
        }

        WorkManagerDebugSection(workSnapshot)

        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun WorkManagerDebugSection(snapshot: WorkManagerDebugSnapshot?) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("WorkManager", style = MaterialTheme.typography.titleMedium)
            DebugInfoRow("Work name", snapshot?.workName ?: TaskSchedulerService.WORK_NAME)
            DebugInfoRow("WorkInfo 件数", "${snapshot?.workInfos?.size ?: 0} 件")
            DebugInfoRow("最終取得時刻", snapshot?.let { formatDebugTime(it.loadedAtMillis) } ?: "-")

            val items = snapshot?.workInfos.orEmpty()
            if (items.isEmpty()) {
                Text(
                    "登録なし",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                items.forEachIndexed { index, item ->
                    HorizontalDivider()
                    Text("WorkInfo #${index + 1}", style = MaterialTheme.typography.titleSmall)
                    DebugInfoRow("id", item.id)
                    DebugInfoRow("state", item.state)
                    DebugInfoRow("nextScheduleTimeMillis", formatNextScheduleTime(item.nextScheduleTimeMillis))
                    DebugInfoRow("initialDelayMillis", formatDurationMillis(item.initialDelayMillis))
                    DebugInfoRow("runAttemptCount", item.runAttemptCount.toString())
                    DebugInfoRow("stopReason", item.stopReason)
                    DebugInfoRow("requiredNetworkType", item.requiredNetworkType)
                    DebugInfoRow("tags", item.tags.joinToString().ifEmpty { "-" })
                }
            }
        }
    }
}

@Composable
private fun DebugSwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun DebugDelayRow(
    label: String,
    value: Int,
    onValueChange: (Int) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(label, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
        OutlinedTextField(
            value = value.toString(),
            onValueChange = { text ->
                val parsed = text.toIntOrNull() ?: return@OutlinedTextField
                onValueChange(parsed.coerceIn(DebugConfig.MIN_DELAY_SECONDS, DebugConfig.MAX_DELAY_SECONDS))
            },
            modifier = Modifier.weight(0.75f),
            label = { Text("秒") },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        )
    }
}

@Composable
private fun DebugInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(0.9f),
        )
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.weight(1.1f),
        )
    }
}

private fun formatNextScheduleTime(epochMs: Long): String =
    when {
        epochMs == Long.MAX_VALUE -> "未予約"
        epochMs <= 0L -> "-"
        else -> formatDebugTime(epochMs)
    }

private fun formatDurationMillis(value: Long): String {
    if (value <= 0L) return "0 秒"
    val totalSeconds = value / 1_000L
    val hours = totalSeconds / 3_600L
    val minutes = (totalSeconds % 3_600L) / 60L
    val seconds = totalSeconds % 60L
    return when {
        hours > 0 -> "${hours}時間 ${minutes}分 ${seconds}秒"
        minutes > 0 -> "${minutes}分 ${seconds}秒"
        else -> "${seconds}秒"
    }
}

private fun formatDebugTime(epochMs: Long): String =
    SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN).format(Date(epochMs))
