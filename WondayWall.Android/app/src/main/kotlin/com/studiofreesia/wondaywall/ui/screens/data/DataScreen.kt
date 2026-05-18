package com.studiofreesia.wondaywall.ui.screens.data

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
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
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.ui.components.FaviconIcon
import com.studiofreesia.wondaywall.ui.util.formatCalendarEventDateTime
import com.studiofreesia.wondaywall.ui.util.formatNewsPublishedAt

// データ画面（カレンダー・RSS・プロンプト設定）
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DataScreen(viewModel: DataViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var newRssUrl by remember { mutableStateOf("") }
    // ユーザープロンプトのローカル編集状態（uiState.userPrompt との同期は LaunchedEffect で行う）
    var promptText by remember { mutableStateOf("") }

    // カレンダー権限リクエストランチャー
    val calendarPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) viewModel.loadData()
    }

    // 外部からプロンプトが変化した場合（初期ロードや保存後）に同期する
    LaunchedEffect(uiState.userPrompt) {
        promptText = uiState.userPrompt
    }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("データ") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {

            // ─── カレンダーセクション ───
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.CalendarMonth, contentDescription = null)
                        Text("カレンダー", style = MaterialTheme.typography.titleMedium)
                    }
                    Spacer(Modifier.height(8.dp))

                    if (!uiState.hasCalendarPermission) {
                        Text(
                            "カレンダーの権限が必要です。",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(8.dp))
                        Button(
                            onClick = {
                                calendarPermissionLauncher.launch(Manifest.permission.READ_CALENDAR)
                            },
                        ) {
                            Text("権限を要求する")
                        }
                    } else {
                        Text(
                            "取得するカレンダーを選択してください。",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(8.dp))

                        // カレンダー一覧
                        uiState.calendarSources.forEach { source ->
                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Checkbox(
                                    checked = source.isSelected,
                                    onCheckedChange = { viewModel.toggleCalendarSelection(source.id) },
                                )
                                Column {
                                    Text(
                                        text = source.displayName,
                                        style = MaterialTheme.typography.bodyMedium,
                                    )
                                    Text(
                                        text = source.accountName,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }

                        if (uiState.calendarSources.isEmpty()) {
                            Text(
                                "端末にカレンダーが見つかりませんでした。",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }

                        // 直近の予定プレビュー
                        if (uiState.calendarEvents.isNotEmpty()) {
                            Spacer(Modifier.height(8.dp))
                            Text(
                                "直近の予定（${uiState.calendarEvents.size}件）",
                                style = MaterialTheme.typography.labelMedium,
                            )
                            uiState.calendarEvents.take(3).forEach { event ->
                                Text(
                                    text = "・${event.title}  ${formatCalendarEventDateTime(event)}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }

            // ─── RSS ソースセクション ───
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.Newspaper, contentDescription = null)
                        Text("RSS ソース", style = MaterialTheme.typography.titleMedium)
                    }
                    Spacer(Modifier.height(8.dp))

                    // ニュースサイト URL 追加フィールド
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        OutlinedTextField(
                            value = newRssUrl,
                            onValueChange = { newRssUrl = it },
                            modifier = Modifier.weight(1f),
                            placeholder = { Text("ニュースサイト URL") },
                            singleLine = true,
                        )
                        IconButton(
                            onClick = {
                                viewModel.addRssSource(newRssUrl.trim()) {
                                    newRssUrl = ""
                                }
                            },
                        ) {
                            Icon(Icons.Default.Add, contentDescription = "追加")
                        }
                    }

                    Spacer(Modifier.height(8.dp))
                    uiState.rssSources.forEach { url ->
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            FaviconIcon(url = url, size = 24.dp)
                            Text(
                                text = url,
                                modifier = Modifier.weight(1f),
                                style = MaterialTheme.typography.bodySmall,
                                maxLines = 1,
                            )
                            IconButton(onClick = { viewModel.removeRssSource(url) }) {
                                Icon(Icons.Default.Close, contentDescription = "削除")
                            }
                        }
                    }

                    // ニューストピックプレビュー
                    if (uiState.isLoadingNews) {
                        CircularProgressIndicator(modifier = Modifier.padding(8.dp))
                    } else if (uiState.newsTopics.isNotEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            "取得済みニュース（${uiState.newsTopics.size}件）",
                            style = MaterialTheme.typography.labelMedium,
                        )
                        uiState.newsTopics.take(3).forEach { news ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                FaviconIcon(url = news.url, size = 24.dp)
                                Column(
                                    modifier = Modifier.weight(1f),
                                    verticalArrangement = Arrangement.spacedBy(2.dp),
                                ) {
                                    Text(
                                        text = news.title,
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 2,
                                    )
                                    Text(
                                        text = formatNewsPublishedAt(news.publishedAt),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // ─── ユーザープロンプトセクション ───
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.TextFields, contentDescription = null)
                        Text("ユーザープロンプト", style = MaterialTheme.typography.titleMedium)
                    }
                    Spacer(Modifier.height(8.dp))
                    Text(
                        "生成に追加する指示・制約を入力してください。",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = promptText,
                        onValueChange = { promptText = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("例: 水彩画風、青系統で統一して") },
                        minLines = 3,
                    )
                    Spacer(Modifier.height(8.dp))
                    Button(
                        onClick = { viewModel.saveUserPrompt(promptText) },
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text("保存する")
                    }
                }
            }
        }
    }
}
