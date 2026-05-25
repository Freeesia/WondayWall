package com.studiofreesia.wondaywall.ui.screens.history

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.studiofreesia.wondaywall.models.GenerationStatus
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.ui.util.canDisplayImageReference
import com.studiofreesia.wondaywall.ui.util.imageReferenceModel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// 履歴画面
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel,
    onNavigateToDetail: (String) -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var deleteTarget by remember { mutableStateOf<HistoryItem?>(null) }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("履歴") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        if (uiState.historyItems.isEmpty()) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Icon(
                        Icons.Default.History,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = "まだ履歴がありません",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 16.dp),
            ) {
                items(
                    items = uiState.historyItems,
                    key = { it.id },
                ) { item ->
                    HistoryItemCard(
                        item = item,
                        onClick = { onNavigateToDetail(item.id) },
                        onDelete = { deleteTarget = item },
                    )
                }
            }
        }
    }

    // 削除確認ダイアログ
    deleteTarget?.let { item ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("履歴を削除") },
            text = { Text("この履歴アイテムを削除しますか？") },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteItem(item.id)
                        deleteTarget = null
                    },
                ) {
                    Text("削除", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) {
                    Text("キャンセル")
                }
            },
        )
    }
}

// 履歴アイテムカード（タップで詳細へ遷移）
@Composable
private fun HistoryItemCard(
    item: HistoryItem,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current

    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // サムネイル
            val imageReference = item.appliedImageUri
            if (imageReference != null && canDisplayImageReference(imageReference)) {
                AsyncImage(
                    model = ImageRequest.Builder(context).data(imageReferenceModel(imageReference)).build(),
                    contentDescription = "壁紙サムネイル",
                    modifier = Modifier
                        .width(56.dp)
                        .aspectRatio(9f / 16f),
                    contentScale = ContentScale.Crop,
                )
            } else {
                Box(
                    modifier = Modifier
                        .width(56.dp)
                        .aspectRatio(9f / 16f),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Default.Image,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // メタデータ列
            Column(modifier = Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    // ステータスアイコン
                    when {
                        item.isGenerating -> Icon(
                            Icons.Default.AutoAwesome,
                            contentDescription = "生成中",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(16.dp),
                        )
                        item.isSkipped -> Icon(
                            Icons.Default.SkipNext,
                            contentDescription = "スキップ",
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.size(16.dp),
                        )
                        item.isSuccess -> Icon(
                            Icons.Default.Check,
                            contentDescription = "成功",
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(16.dp),
                        )
                        else -> Icon(
                            Icons.Default.Error,
                            contentDescription = "失敗",
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                    Text(
                        text = SimpleDateFormat("yyyy/MM/dd HH:mm", Locale.JAPAN)
                            .format(Date(item.executedAt.toEpochMilliseconds())),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // エラーサマリー
                if (!item.isSuccess && !item.isGenerating && item.errorSummary != null) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = item.errorSummary,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                        maxLines = 2,
                    )
                }

                // 使用した予定・ニュース数
                val eventsCount = item.usedCalendarEvents?.size ?: 0
                val newsCount = item.usedNewsTopics?.size ?: 0
                if (eventsCount > 0 || newsCount > 0) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = buildString {
                            if (eventsCount > 0) append("予定 ${eventsCount}件  ")
                            if (newsCount > 0) append("ニュース ${newsCount}件")
                        }.trim(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (item.isGenerating) {
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = generationStatusLabel(item.status),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            // 削除ボタン
            IconButton(onClick = onDelete) {
                Icon(
                    Icons.Default.Delete,
                    contentDescription = "削除",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun generationStatusLabel(status: GenerationStatus): String = when (status) {
    GenerationStatus.Generating -> "生成中"
    GenerationStatus.GeneratingPromptReady -> "プロンプト生成済み"
    GenerationStatus.GeneratingImageRequested -> "画像生成リクエスト済み"
    GenerationStatus.Success -> "成功"
    GenerationStatus.Skipped -> "スキップ"
    GenerationStatus.Failure -> "失敗"
}
