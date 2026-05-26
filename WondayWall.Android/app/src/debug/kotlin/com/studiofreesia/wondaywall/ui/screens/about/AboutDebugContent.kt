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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.BuildConfig
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.DebugConfig
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.DummyAiService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.AiService
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import com.studiofreesia.wondaywall.services.ScheduleDebugReader
import com.studiofreesia.wondaywall.services.ScheduleDebugSnapshot
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
    val scheduleDebugReader = remember(taskSchedulerService) { ScheduleDebugReader(taskSchedulerService) }
    val isGenerating by generationCoordinator.isGenerating.collectAsState()
    val generationProgress by generationCoordinator.progress.collectAsState()
    val scope = rememberCoroutineScope()
    var config by remember { mutableStateOf<AppConfig?>(null) }
    var debugConfig by remember { mutableStateOf(DebugConfig()) }
    var scheduleSnapshot by remember { mutableStateOf<ScheduleDebugSnapshot?>(null) }
    var loadedAt by remember { mutableLongStateOf(0L) }

    fun reload() {
        scope.launch {
            val loadedConfig = appConfigService.getConfig()
            config = loadedConfig
            debugConfig = appConfigService.getDebugConfig()
            scheduleSnapshot = scheduleDebugReader.loadSnapshot()
            loadedAt = System.currentTimeMillis()
        }
    }

    fun updateDebugConfig(update: (DebugConfig) -> DebugConfig) {
        scope.launch {
            val updated = update(debugConfig).normalized()
            appConfigService.saveDebugConfig(updated)
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
                DebugInfoRow("ビルド種別", BuildConfig.BUILD_TYPE)
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

        ScheduleDebugSection(scheduleSnapshot)

        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun ScheduleDebugSection(snapshot: ScheduleDebugSnapshot?) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("定時アラーム", style = MaterialTheme.typography.titleMedium)
            DebugInfoRow("管理方式", "AlarmManager")
            DebugInfoRow("Alarm 登録", snapshot?.let { if (it.alarmRegistered) "YES" else "NO" } ?: "-")
            DebugInfoRow("次回スロット", formatOptionalDebugTime(snapshot?.expectedNextAlarmTimeMillis))
            DebugInfoRow("最終取得時刻", snapshot?.let { formatDebugTime(it.loadedAtMillis) } ?: "-")
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

private fun formatOptionalDebugTime(epochMs: Long?): String =
    epochMs?.let(::formatDebugTime) ?: "-"

private fun formatDebugTime(epochMs: Long): String =
    SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN).format(Date(epochMs))
