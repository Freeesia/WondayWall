package com.studiofreesia.wondaywall.ui.screens.home

import android.content.Intent
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BrokenImage
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.services.WallpaperService
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// ホーム画面
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(viewModel: HomeViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current

    // エラー表示
    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(title = { Text("WondayWall") })
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // 最新生成画像プレビューカード
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "最新の壁紙",
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Spacer(Modifier.height(8.dp))

                    val imagePath = uiState.latestHistoryItem?.appliedImagePath
                    if (imagePath != null && File(imagePath).exists()) {
                        AsyncImage(
                            model = ImageRequest.Builder(context)
                                .data(File(imagePath))
                                .build(),
                            contentDescription = "最新の壁紙",
                            modifier = Modifier
                                .fillMaxWidth()
                                .aspectRatio(9f / 16f),
                            contentScale = ContentScale.Crop,
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .aspectRatio(9f / 16f),
                            contentAlignment = Alignment.Center,
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    Icons.Default.Image,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                Text(
                                    text = "壁紙がまだ生成されていません",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                    }
                }
            }

            // 生成ボタン
            Button(
                onClick = { viewModel.generateNow() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !uiState.isGenerating,
            ) {
                if (uiState.isGenerating) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .height(20.dp)
                            .padding(end = 8.dp),
                        strokeWidth = 2.dp,
                    )
                    Text("生成中…")
                } else {
                    Icon(Icons.Default.Refresh, contentDescription = null)
                    Text("  今すぐ生成", modifier = Modifier.padding(start = 4.dp))
                }
            }

            // 直近の実行結果カード
            uiState.latestHistoryItem?.let { item ->
                ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                imageVector = if (item.isSuccess) Icons.Default.Check else Icons.Default.Error,
                                contentDescription = null,
                                tint = if (item.isSuccess) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.error,
                            )
                            Text(
                                text = if (item.isSuccess) "生成成功" else "生成失敗",
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Spacer(Modifier.weight(1f))
                            Text(
                                text = formatInstant(item.executedAt.toEpochMilliseconds()),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        if (!item.isSuccess && item.errorSummary != null) {
                            Spacer(Modifier.height(4.dp))
                            Text(
                                text = item.errorSummary,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                        }

                        // 画像操作ボタン
                        if (item.appliedImagePath != null) {
                            Spacer(Modifier.height(8.dp))
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                FilledTonalButton(
                                    onClick = { viewModel.applyWallpaper(item.appliedImagePath) },
                                    modifier = Modifier.weight(1f),
                                ) {
                                    Icon(
                                        Icons.Default.Wallpaper,
                                        contentDescription = null,
                                    )
                                    Text("  適用", modifier = Modifier.padding(start = 4.dp))
                                }
                                IconButton(
                                    onClick = {
                                        viewModel.saveToGallery(item.appliedImagePath) { success ->
                                            // 結果は Snackbar で通知する（ViewModel 経由）
                                        }
                                    },
                                ) {
                                    Icon(Icons.Default.PhotoLibrary, contentDescription = "ギャラリーに保存")
                                }
                                IconButton(
                                    onClick = {
                                        // WallpaperService から share Intent を取得して起動する
                                        // （ViewModel 外部の処理のため Activity で実行する）
                                    },
                                ) {
                                    Icon(Icons.Default.Share, contentDescription = "共有")
                                }
                            }
                        }
                    }
                }
            }

            // ロック画面更新設定の表示
            if (uiState.config.updateLockScreen) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = "ロック画面も更新します",
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // 自動生成の状態表示
            if (uiState.config.autoGenerationEnabled) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Text(
                        text = "自動生成: ${uiState.config.runsPerDay}回/日",
                        modifier = Modifier.padding(12.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// エポックミリ秒を読みやすい文字列に変換する
private fun formatInstant(epochMs: Long): String {
    val sdf = SimpleDateFormat("MM/dd HH:mm", Locale.JAPAN)
    return sdf.format(Date(epochMs))
}
