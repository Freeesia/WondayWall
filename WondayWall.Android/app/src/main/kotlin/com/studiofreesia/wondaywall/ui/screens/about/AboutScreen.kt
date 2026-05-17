package com.studiofreesia.wondaywall.ui.screens.about

import android.content.Context
import android.graphics.drawable.BitmapDrawable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.BugReport
import androidx.compose.material.icons.filled.Code
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import com.studiofreesia.wondaywall.BuildConfig

// アプリ情報画面（iOS の AboutView 相当）
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val versionName = remember { context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "?" }

    // アプリアイコンを PackageManager から取得する
    val appIconBitmap = remember {
        try {
            val drawable = context.packageManager.getApplicationIcon(context.packageName)
            (drawable as? BitmapDrawable)?.bitmap ?: drawable.toBitmap()
        } catch (e: Exception) {
            null
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("アプリについて") },
                navigationIcon = {
                    TextButton(onClick = onBack) {
                        Text("戻る")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // アプリアイコンと名前・バージョン
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                appIconBitmap?.let { bitmap ->
                    Image(
                        bitmap = bitmap.asImageBitmap(),
                        contentDescription = "アプリアイコン",
                        modifier = Modifier
                            .size(80.dp)
                            .clip(RoundedCornerShape(18.dp)),
                    )
                }
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

            // リンク一覧
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
                // デバッグ情報セクション（デバッグビルドのみ表示）
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    AboutLinkRow(
                        icon = Icons.Default.BugReport,
                        title = "デバッグ情報",
                        onClick = { /* TODO: デバッグ情報シート */ },
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }
}

// リンク行コンポーネント
@Composable
private fun AboutLinkRow(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
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
                Icons.AutoMirrored.Filled.OpenInNew,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
