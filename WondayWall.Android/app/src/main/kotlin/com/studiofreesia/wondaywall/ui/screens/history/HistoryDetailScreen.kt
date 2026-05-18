package com.studiofreesia.wondaywall.ui.screens.history

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.TextSnippet
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.ui.components.FaviconIcon
import com.studiofreesia.wondaywall.ui.util.formatCalendarEventDateTime
import com.studiofreesia.wondaywall.ui.util.formatNewsPublishedAt
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// 履歴詳細画面（iOSのHistoryDetailViewと同等）
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryDetailScreen(
    item: HistoryItem,
    onBack: () -> Unit,
) {
    val context = LocalContext.current
    val uriHandler = LocalUriHandler.current
    val dateStr = remember(item.executedAt) {
        SimpleDateFormat("yyyy/MM/dd", Locale.JAPAN).format(Date(item.executedAt.toEpochMilliseconds()))
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(dateStr) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "戻る")
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
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 画像プレビュー（成功時のみ表示）
            val imagePath = item.appliedImagePath
            if (item.isSuccess && imagePath != null && File(imagePath).exists()) {
                AsyncImage(
                    model = ImageRequest.Builder(context).data(File(imagePath)).build(),
                    contentDescription = "生成された壁紙",
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(9f / 16f)
                        .clip(RoundedCornerShape(16.dp)),
                    contentScale = ContentScale.Crop,
                )
            }

            // ステータスバッジ
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    when {
                        item.isSkipped -> Icon(
                            Icons.Default.SkipNext,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        item.isSuccess -> Icon(
                            Icons.Default.Check,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        else -> Icon(
                            Icons.Default.Error,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                    }
                    Text(
                        text = when {
                            item.isSkipped -> "スキップ"
                            item.isSuccess -> "成功"
                            else -> "失敗"
                        },
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = SimpleDateFormat("HH:mm", Locale.JAPAN)
                            .format(Date(item.executedAt.toEpochMilliseconds())),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // 使用した予定セクション
            val events = item.usedCalendarEvents.orEmpty()
            if (events.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = null)
                        Text("使用した予定", style = MaterialTheme.typography.titleSmall)
                    }
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column {
                            events.forEachIndexed { index, event ->
                                if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                                Column(
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(horizontal = 12.dp, vertical = 10.dp),
                                ) {
                                    Text(event.title, style = MaterialTheme.typography.bodyMedium)
                                    Text(
                                        text = formatCalendarEventDateTime(event),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // 使用したニュースセクション
            val news = item.usedNewsTopics.orEmpty()
            if (news.isNotEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.Newspaper, contentDescription = null)
                        Text("使用したニュース", style = MaterialTheme.typography.titleSmall)
                    }
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Column {
                            news.forEachIndexed { index, newsItem ->
                                if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                                val content: @Composable () -> Unit = {
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(horizontal = 12.dp, vertical = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    ) {
                                        FaviconIcon(url = newsItem.url)
                                        Column(
                                            modifier = Modifier.weight(1f),
                                            verticalArrangement = Arrangement.spacedBy(2.dp),
                                        ) {
                                            Text(
                                                text = newsItem.title,
                                                style = MaterialTheme.typography.bodyMedium,
                                                maxLines = 3,
                                            )
                                            Text(
                                                text = formatNewsPublishedAt(newsItem.publishedAt),
                                                style = MaterialTheme.typography.bodySmall,
                                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                            )
                                        }
                                    }
                                }
                                if (!newsItem.url.isNullOrEmpty()) {
                                    // URLがある場合はタップでリンクを開く
                                    TextButton(
                                        onClick = { uriHandler.openUri(newsItem.url) },
                                        modifier = Modifier.fillMaxWidth(),
                                        shape = RoundedCornerShape(0.dp),
                                    ) { content() }
                                } else {
                                    content()
                                }
                            }
                        }
                    }
                }
            }

            // 使用したプロンプトセクション
            val prompt = item.usedPrompt
            if (!prompt.isNullOrEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.AutoMirrored.Filled.TextSnippet, contentDescription = null)
                        Text("使用したプロンプト", style = MaterialTheme.typography.titleSmall)
                    }
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = prompt,
                            modifier = Modifier.padding(12.dp),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }
                }
            }

            // エラー詳細セクション
            val error = item.errorSummary
            if (!error.isNullOrEmpty()) {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                        )
                        Text(
                            "エラー詳細",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = error,
                            modifier = Modifier.padding(12.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(Modifier.height(16.dp))
        }
    }
}
