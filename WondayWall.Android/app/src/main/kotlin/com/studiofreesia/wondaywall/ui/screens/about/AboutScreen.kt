package com.studiofreesia.wondaywall.ui.screens.about

import android.content.Context
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.BuildConfig
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import com.studiofreesia.wondaywall.ui.components.SquareAppIcon
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.launch

// アプリ情報シート（iOS の AboutView 相当）
@Composable
fun AboutScreen(
    appConfigService: AppConfigService,
    generationCoordinator: GenerationCoordinator,
    onClose: () -> Unit,
) {
    var showDebugInfo by remember { mutableStateOf(false) }

    if (showDebugInfo) {
        DebugInfoContent(
            appConfigService = appConfigService,
            generationCoordinator = generationCoordinator,
            onBack = { showDebugInfo = false },
            onClose = onClose,
        )
    } else {
        AboutContent(
            onClose = onClose,
            onShowDebugInfo = { showDebugInfo = true },
        )
    }
}

@Composable
private fun AboutContent(
    onClose: () -> Unit,
    onShowDebugInfo: () -> Unit,
) {
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val versionName = remember { appVersionName(context) }

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
            Text(
                "アプリについて",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onClose) {
                Text("閉じる")
            }
        }

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SquareAppIcon()
            Text("WondayWall", style = MaterialTheme.typography.titleLarge)
            Text(
                "Version $versionName",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                "by Freeesia (StudioFreesia)",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column {
                AboutLinkRow(
                    icon = Icons.Default.Language,
                    title = "公式サイト",
                    onClick = { uriHandler.openUri("https://ww.studiofreesia.com/") },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                AboutLinkRow(
                    icon = Icons.Default.Lock,
                    title = "プライバシーポリシー",
                    onClick = { uriHandler.openUri("https://ww.studiofreesia.com/PrivacyPolicy") },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                AboutLinkRow(
                    icon = Icons.Default.Description,
                    title = "利用規約",
                    onClick = { uriHandler.openUri("https://ww.studiofreesia.com/Terms_of_Use") },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                AboutLinkRow(
                    icon = Icons.Default.Image,
                    title = "生成画像の利用について",
                    onClick = { uriHandler.openUri("https://ww.studiofreesia.com/GeneratedImageUsage") },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                AboutLinkRow(
                    icon = Icons.Default.NotificationsNone,
                    title = "リリースノート",
                    onClick = { uriHandler.openUri("https://github.com/Freeesia/WondayWall/releases") },
                )
                HorizontalDivider(modifier = Modifier.padding(start = 52.dp))
                AboutLinkRow(
                    icon = Icons.Default.Code,
                    title = "GitHub",
                    onClick = { uriHandler.openUri("https://github.com/Freeesia/WondayWall") },
                )
            }
        }

        if (BuildConfig.DEBUG) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                AboutLinkRow(
                    icon = Icons.Default.BugReport,
                    title = "デバッグ情報",
                    trailingIcon = Icons.Default.ChevronRight,
                    onClick = onShowDebugInfo,
                )
            }
        }

        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun DebugInfoContent(
    appConfigService: AppConfigService,
    generationCoordinator: GenerationCoordinator,
    onBack: () -> Unit,
    onClose: () -> Unit,
) {
    val isGenerating by generationCoordinator.isGenerating.collectAsState()
    val scope = rememberCoroutineScope()
    var config by remember { mutableStateOf<AppConfig?>(null) }
    var loadedAt by remember { mutableLongStateOf(0L) }

    fun reload() {
        scope.launch {
            config = appConfigService.getConfig()
            loadedAt = System.currentTimeMillis()
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
                DebugInfoRow("ビルド種別", if (BuildConfig.DEBUG) "Debug" else "Release")
                DebugInfoRow("生成中", if (isGenerating) "YES" else "NO")
                DebugInfoRow("自動生成", if (config?.autoGenerationEnabled == true) "ON" else "OFF")
                DebugInfoRow("API キー", if (config?.googleAiApiKey?.isNotBlank() == true) "設定済み" else "未設定")
                DebugInfoRow("スケジュール", config?.schedule?.displayName() ?: "-")
                DebugInfoRow("対象カレンダー", "${config?.targetCalendarIds?.size ?: 0} 件")
                DebugInfoRow("RSS ソース", "${config?.rssSources?.size ?: 0} 件")
                DebugInfoRow("WorkManager", TaskSchedulerService.WORK_NAME)
                DebugInfoRow("最終取得", if (loadedAt > 0) formatDebugTime(loadedAt) else "-")
            }
        }

        Spacer(Modifier.height(16.dp))
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

@Composable
private fun AboutLinkRow(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    trailingIcon: ImageVector = Icons.AutoMirrored.Filled.OpenInNew,
) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(0.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                icon,
                contentDescription = null,
                modifier = Modifier.size(28.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f),
            )
            Icon(
                trailingIcon,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun appVersionName(context: Context): String =
    context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "?"

private fun formatDebugTime(epochMs: Long): String =
    SimpleDateFormat("yyyy/MM/dd HH:mm:ss", Locale.JAPAN).format(Date(epochMs))
