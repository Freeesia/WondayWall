package com.studiofreesia.wondaywall.ui.screens.home

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.ui.components.FaviconIcon
import com.studiofreesia.wondaywall.ui.util.formatCalendarEventDateTime
import com.studiofreesia.wondaywall.ui.util.formatNewsPublishedAt
import java.io.File

// ホーム画面（iOSのHomeViewと同等の構成）
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(viewModel: HomeViewModel) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var isGenerationSheetFullScreen by remember { mutableStateOf(false) }

    // エラー表示
    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    LaunchedEffect(uiState.showGenerationSheet) {
        if (uiState.showGenerationSheet) {
            isGenerationSheetFullScreen = false
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        // 壁紙生成フローティングボタン（右下）
        floatingActionButton = {
            Button(
                onClick = {
                    if (!uiState.isGenerating) {
                        viewModel.openGenerationSheet()
                    }
                },
                enabled = !uiState.isGenerating,
                shape = RoundedCornerShape(50),
            ) {
                if (uiState.isGenerating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                        color = Color.White,
                    )
                    Spacer(Modifier.size(8.dp))
                    Text(uiState.generationProgress?.let { "生成中 ${it.percent}%" } ?: "生成中...")
                } else {
                    Icon(Icons.Default.AutoAwesome, contentDescription = null)
                    Spacer(Modifier.size(8.dp))
                    Text("壁紙生成")
                }
            }
        },
    ) { padding ->
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .padding(bottom = padding.calculateBottomPadding()),
        ) {
            val wallpaperPeekHeight = maxHeight * 2f / 3f
            val usedInfoBackground = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f)
            val imagePath = uiState.latestHistoryItem?.appliedImagePath
            if (imagePath != null && File(imagePath).exists()) {
                // 最新壁紙を全画面背景として表示する
                AsyncImage(
                    model = ImageRequest.Builder(context)
                        .data(File(imagePath))
                        .build(),
                    contentDescription = "最新の壁紙",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
            } else {
                // 壁紙がない場合はプレースホルダーを表示する
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            Icons.Default.Image,
                            contentDescription = null,
                            modifier = Modifier.size(64.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = "まだ壁紙がありません",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }

            // スクロール可能なコンテンツ（背景画像の上に重ねる）
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
            ) {
                val latestHistory = uiState.latestHistoryItem
                val events = latestHistory?.usedCalendarEvents.orEmpty()
                val news = latestHistory?.usedNewsTopics.orEmpty()

                if (imagePath != null && (events.isNotEmpty() || news.isNotEmpty())) {
                    // 画像を見せるための空白（画面の2/3）
                    Spacer(modifier = Modifier.height(wallpaperPeekHeight))
                }

                if (events.isNotEmpty()) {
                    // グラデーションによる自然な境界線
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(24.dp)
                            .background(
                                brush = Brush.verticalGradient(
                                    colors = listOf(Color.Transparent, usedInfoBackground),
                                )
                            )
                    )
                    // 使用した予定セクション
                    UsedEventsSection(
                        events = events,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(usedInfoBackground)
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }

                if (news.isNotEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(24.dp)
                            .background(
                                brush = Brush.verticalGradient(
                                    colors = listOf(Color.Transparent, usedInfoBackground),
                                )
                            )
                    )
                    // 使用したニュースセクション
                    UsedNewsSection(
                        news = news,
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(usedInfoBackground)
                            .padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }

                // FAB 分の余白
                Spacer(Modifier.height(80.dp))
            }
        }
    }

    // 壁紙生成確認シート
    if (uiState.showGenerationSheet) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.dismissGenerationSheet() },
            sheetState = sheetState,
            dragHandle = { BottomSheetDefaults.DragHandle() },
        ) {
            GenerationConfirmSheet(
                uiState = uiState,
                viewModel = viewModel,
                isFullScreen = isGenerationSheetFullScreen,
                onToggleFullScreen = {
                    isGenerationSheetFullScreen = !isGenerationSheetFullScreen
                },
            )
        }
    }
}

// 壁紙生成確認シート本体
@Composable
private fun GenerationConfirmSheet(
    uiState: HomeUiState,
    viewModel: HomeViewModel,
    isFullScreen: Boolean,
    onToggleFullScreen: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (isFullScreen) {
                    Modifier.fillMaxHeight()
                } else {
                    Modifier.heightIn(max = 560.dp)
                }
            )
            .windowInsetsPadding(WindowInsets.navigationBars),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 88.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "壁紙を生成する",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onToggleFullScreen) {
                    Icon(
                        imageVector = if (isFullScreen) {
                            Icons.Default.FullscreenExit
                        } else {
                            Icons.Default.Fullscreen
                        },
                        contentDescription = if (isFullScreen) {
                            "通常表示に戻す"
                        } else {
                            "全画面表示にする"
                        },
                    )
                }
            }

            GenerationSheetData(uiState = uiState)
        }

        // 生成ボタン
        Button(
            onClick = { viewModel.generateFromSheet() },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 16.dp),
            enabled = !uiState.isGenerating && !uiState.isLoadingSheetData,
        ) {
            if (uiState.isLoadingSheetData) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                    color = Color.White,
                )
                Spacer(Modifier.size(8.dp))
            } else {
                Icon(Icons.Default.AutoAwesome, contentDescription = null)
                Spacer(Modifier.size(8.dp))
            }
            Text("生成！")
        }
    }
}

@Composable
private fun GenerationSheetData(uiState: HomeUiState) {
    if (uiState.isLoadingSheetData) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(120.dp),
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator()
        }
        return
    }

    if (uiState.sheetEvents.isNotEmpty()) {
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(12.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Default.CalendarMonth, contentDescription = null)
                    Text("カレンダー予定", style = MaterialTheme.typography.titleSmall)
                }
                Spacer(Modifier.height(8.dp))
                uiState.sheetEvents.forEachIndexed { index, event ->
                    if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp),
                    ) {
                        Text(event.title, style = MaterialTheme.typography.bodyMedium)
                        Text(
                            formatCalendarEventDateTime(event),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }

    if (uiState.sheetNews.isNotEmpty()) {
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(12.dp)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Default.Newspaper, contentDescription = null)
                    Text("ニュース", style = MaterialTheme.typography.titleSmall)
                }
                Spacer(Modifier.height(8.dp))
                uiState.sheetNews.forEachIndexed { index, item ->
                    if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        FaviconIcon(url = item.url)
                        Column(
                            modifier = Modifier.weight(1f),
                            verticalArrangement = Arrangement.spacedBy(2.dp),
                        ) {
                            Text(
                                text = item.title,
                                style = MaterialTheme.typography.bodyMedium,
                                maxLines = 2,
                            )
                            Text(
                                text = formatNewsPublishedAt(item.publishedAt),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }

    if (uiState.sheetEvents.isEmpty() && uiState.sheetNews.isEmpty()) {
        Text(
            "利用できるカレンダー予定・ニュースがありません",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 8.dp),
        )
    }
}

// 使用した予定セクション
@Composable
private fun UsedEventsSection(
    events: List<CalendarEventItem>,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
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
                            formatCalendarEventDateTime(event),
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
@Composable
private fun UsedNewsSection(
    news: List<NewsTopicItem>,
    modifier: Modifier = Modifier,
) {
    val uriHandler = LocalUriHandler.current

    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Default.Newspaper, contentDescription = null)
            Text("使用したニュース", style = MaterialTheme.typography.titleSmall)
        }
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column {
                news.forEachIndexed { index, item ->
                    if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                    val content: @Composable () -> Unit = {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            FaviconIcon(url = item.url)
                            Column(
                                modifier = Modifier.weight(1f),
                                verticalArrangement = Arrangement.spacedBy(2.dp),
                            ) {
                                Text(
                                    text = item.title,
                                    style = MaterialTheme.typography.bodyMedium,
                                    maxLines = 2,
                                )
                                Text(
                                    text = formatNewsPublishedAt(item.publishedAt),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                    if (!item.url.isNullOrEmpty()) {
                        // URLがある場合はタップでリンクを開く
                        androidx.compose.material3.TextButton(
                            onClick = { uriHandler.openUri(item.url) },
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
