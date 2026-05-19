package com.studiofreesia.wondaywall.ui.screens.wizard

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.ArrowForward
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Image
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Wallpaper
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.studiofreesia.wondaywall.models.UpdateSchedule
import com.studiofreesia.wondaywall.ui.components.FaviconIcon
import com.studiofreesia.wondaywall.ui.components.SquareAppIcon
import java.io.File

// ウィザード画面（セットアップ）
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WizardScreen(
    viewModel: WizardViewModel,
    onComplete: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val canGoNext = uiState.currentStep != 1 || uiState.apiKey.isNotBlank()

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .imePadding(),
        ) {
            // プログレスバー
            LinearProgressIndicator(
                progress = { (uiState.currentStep + 1).toFloat() / WIZARD_TOTAL_STEPS },
                modifier = Modifier.fillMaxWidth(),
            )

            // ステップコンテンツ（アニメーション付き切り替え）
            Box(modifier = Modifier.weight(1f)) {
                AnimatedContent(
                    targetState = uiState.currentStep,
                    transitionSpec = {
                        if (targetState > initialState) {
                            slideInHorizontally { it } togetherWith slideOutHorizontally { -it }
                        } else {
                            slideInHorizontally { -it } togetherWith slideOutHorizontally { it }
                        }
                    },
                    label = "wizard_step",
                ) { step ->
                    when (step) {
                        0 -> StepWelcome()
                        1 -> StepApiKey(uiState, viewModel)
                        2 -> StepCalendar(uiState, viewModel)
                        3 -> StepPromptAndRss(uiState, viewModel)
                        4 -> StepSchedule(uiState, viewModel)
                        5 -> StepTestGenerate(uiState, viewModel)
                    }
                }
            }

            // ナビゲーションボタン行
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (uiState.currentStep > 0) {
                    OutlinedButton(onClick = { viewModel.prevStep() }) {
                        Icon(Icons.Default.ArrowBack, contentDescription = null)
                        Text("  戻る")
                    }
                } else {
                    Spacer(Modifier.width(1.dp))
                }

                Text(
                    text = "${uiState.currentStep + 1} / $WIZARD_TOTAL_STEPS",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                if (uiState.currentStep < WIZARD_TOTAL_STEPS - 1) {
                    Button(
                        onClick = { viewModel.nextStep() },
                        enabled = canGoNext,
                    ) {
                        Text("次へ  ")
                        Icon(Icons.Default.ArrowForward, contentDescription = null)
                    }
                } else {
                    Button(
                        onClick = { viewModel.completeWizard(onComplete) },
                        enabled = !uiState.isCompleting && !uiState.isTestGenerating,
                    ) {
                        if (uiState.isCompleting || uiState.isTestGenerating) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                            Text("  完了中…")
                        } else {
                            Icon(Icons.Default.Check, contentDescription = null)
                            Text("  完了")
                        }
                    }
                }
            }
        }
    }
}

// ステップ 1: ようこそ
@Composable
private fun StepWelcome() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(32.dp),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SquareAppIcon()
        Spacer(Modifier.height(24.dp))
        Text(
            text = "WondayWall へようこそ",
            style = MaterialTheme.typography.headlineMedium,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(16.dp))
        Text(
            text = "カレンダーの予定やニュースをもとに、\nAI があなた専用の壁紙を自動生成します。\n\n数ステップでセットアップを完了しましょう。",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ステップ 2: API キー入力
@Composable
private fun StepApiKey(uiState: WizardUiState, viewModel: WizardViewModel) {
    val uriHandler = LocalUriHandler.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Google AI API キー", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "Gemini API を使用するために API キーが必要です。\nGoogle AI Studio から取得してください。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // API キー取得リンク
        TextButton(
            onClick = { uriHandler.openUri("https://aistudio.google.com/apikey") },
        ) {
            Icon(
                Icons.Default.OpenInNew,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
            )
            Spacer(Modifier.width(4.dp))
            Text("API キーを取得する")
        }

        OutlinedTextField(
            value = uiState.apiKey,
            onValueChange = { viewModel.updateApiKey(it) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text("API キー") },
            leadingIcon = { Icon(Icons.Default.Key, contentDescription = null) },
            visualTransformation = PasswordVisualTransformation(),
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
            singleLine = true,
            isError = uiState.apiKey.isBlank(),
            supportingText = {
                if (uiState.apiKey.isBlank()) {
                    Text("API キーは必須です")
                }
            },
        )

        FilledTonalButton(
            onClick = { viewModel.testApiConnection() },
            modifier = Modifier.fillMaxWidth(),
            enabled = uiState.apiKey.isNotBlank() && uiState.apiTestResult !is ApiTestResult.Testing,
        ) {
            when (uiState.apiTestResult) {
                is ApiTestResult.Testing -> {
                    CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    Text("  テスト中…")
                }
                else -> {
                    Text("接続テストを実行")
                }
            }
        }

        // テスト結果表示
        when (val result = uiState.apiTestResult) {
            is ApiTestResult.Success -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Default.Check, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Text("接続成功！", color = MaterialTheme.colorScheme.primary)
            }
            is ApiTestResult.Failure -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Icon(Icons.Default.Error, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                Text(result.message, color = MaterialTheme.colorScheme.error)
            }
            else -> {}
        }
    }
}

// ステップ 3: カレンダー権限
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StepCalendar(uiState: WizardUiState, viewModel: WizardViewModel) {
    val calendarPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) viewModel.onCalendarPermissionGranted()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("カレンダー連携", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "端末のカレンダーと連携することで、予定に合わせた壁紙を生成できます。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (!uiState.hasCalendarPermission) {
            Button(
                onClick = { calendarPermissionLauncher.launch(Manifest.permission.READ_CALENDAR) },
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text("カレンダーへのアクセスを許可する")
            }
        } else {
            Text("取得するカレンダーを選択してください。（複数選択可）", style = MaterialTheme.typography.bodySmall)
            uiState.calendarSources.forEach { source ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Checkbox(
                        checked = uiState.selectedCalendarIds.contains(source.id),
                        onCheckedChange = { viewModel.toggleCalendarSelection(source.id) },
                    )
                    Column {
                        Text(source.displayName, style = MaterialTheme.typography.bodyMedium)
                        Text(
                            source.accountName,
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
        }

        Text(
            text = "カレンダー連携はスキップして後から設定できます。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ステップ 4: プロンプトと RSS
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StepPromptAndRss(uiState: WizardUiState, viewModel: WizardViewModel) {
    var newRssUrl by remember { mutableStateOf("") }

    // プロンプトテンプレート一覧
    val promptTemplates = listOf(
        "水彩画風で生成してください",
        "写実的な風景で生成してください",
        "ミニマルなデザインで生成してください",
        "イラスト・アニメ調で生成してください",
        "油絵風で生成してください",
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("コンテキスト設定", style = MaterialTheme.typography.headlineSmall)

        // ユーザープロンプト
        Text("ユーザープロンプト", style = MaterialTheme.typography.titleMedium)
        Text(
            text = "生成する壁紙のスタイルや制約を指示してください。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // テンプレートチップ
        Text("テンプレート", style = MaterialTheme.typography.labelMedium)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            promptTemplates.forEach { template ->
                FilterChip(
                    selected = uiState.userPrompt == template,
                    onClick = {
                        viewModel.updateUserPrompt(
                            if (uiState.userPrompt == template) "" else template
                        )
                    },
                    label = { Text(template, style = MaterialTheme.typography.labelSmall) },
                )
            }
        }

        OutlinedTextField(
            value = uiState.userPrompt,
            onValueChange = { viewModel.updateUserPrompt(it) },
            modifier = Modifier.fillMaxWidth(),
            placeholder = { Text("例: 水彩画風、青系統で統一して") },
            minLines = 3,
        )

        // RSS ソース
        Text("RSS ニュースソース", style = MaterialTheme.typography.titleMedium)
        Text(
            text = "ニュースを参考にした壁紙を生成したい場合はニュースサイト URL を追加してください。RSS URL の直接入力もできます。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

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
            IconButton(onClick = {
                viewModel.addRssSource(newRssUrl) {
                    newRssUrl = ""
                }
            }) {
                Icon(Icons.Default.Add, contentDescription = "追加")
            }
        }

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
    }
}

// ステップ 5: スケジュール設定
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun StepSchedule(uiState: WizardUiState, viewModel: WizardViewModel) {
    var scheduleDropdownExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("自動生成スケジュール", style = MaterialTheme.typography.headlineSmall)
        Text(
            text = "壁紙を自動で更新する頻度と動作を設定します。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // 更新スケジュール
        ExposedDropdownMenuBox(
            expanded = scheduleDropdownExpanded,
            onExpandedChange = { scheduleDropdownExpanded = it },
        ) {
            OutlinedTextField(
                value = uiState.schedule.displayName(),
                onValueChange = {},
                readOnly = true,
                label = { Text("更新スケジュール") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(scheduleDropdownExpanded) },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(),
            )
            ExposedDropdownMenu(
                expanded = scheduleDropdownExpanded,
                onDismissRequest = { scheduleDropdownExpanded = false },
            ) {
                UpdateSchedule.entries.forEach { schedule ->
                    DropdownMenuItem(
                        text = { Text(schedule.displayName()) },
                        onClick = {
                            viewModel.updateSchedule(schedule)
                            scheduleDropdownExpanded = false
                        },
                    )
                }
            }
        }

        WizardSwitchRow("Wi-Fi 接続時のみ生成する", uiState.wifiOnly, viewModel::toggleWifiOnly)
        WizardSwitchRow("省電力モード中はスキップ", uiState.skipOnBatterySaver, viewModel::toggleSkipOnBatterySaver)
        WizardSwitchRow("通知を表示する", uiState.showNotification, viewModel::toggleShowNotification)
        WizardSwitchRow("ロック画面も更新する", uiState.updateLockScreen, viewModel::toggleUpdateLockScreen)
    }
}

// ステップ 6: テスト生成
@Composable
private fun StepTestGenerate(uiState: WizardUiState, viewModel: WizardViewModel) {
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp)
            .verticalScroll(rememberScrollState()),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            text = "テスト生成",
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.fillMaxWidth(),
        )
        Text(
            text = "設定が完了しました。\nテスト生成を実行して壁紙プレビューを確認できます。",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth(),
        )

        // テスト生成ボタン
        FilledTonalButton(
            onClick = { viewModel.testGenerate() },
            modifier = Modifier.fillMaxWidth(),
            enabled = !uiState.isTestGenerating,
        ) {
            if (uiState.isTestGenerating) {
                CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                Text("  生成中…（最大10分かかる場合があります）")
            } else {
                Icon(Icons.Default.Refresh, contentDescription = null)
                Text("  テスト生成を実行")
            }
        }

        // 生成結果プレビュー
        val imagePath = uiState.testGenerationImagePath
        if (imagePath != null && File(imagePath).exists()) {
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                AsyncImage(
                    model = ImageRequest.Builder(context).data(File(imagePath)).build(),
                    contentDescription = "テスト生成プレビュー",
                    modifier = Modifier
                        .fillMaxWidth()
                        .aspectRatio(9f / 16f),
                    contentScale = ContentScale.Crop,
                )
            }
        } else if (!uiState.isTestGenerating) {
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
                        modifier = Modifier.size(48.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text(
                        text = "「テスト生成を実行」を押すと\nプレビューが表示されます",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }
        }

        Text(
            text = "「完了」を押すと設定が保存され、\n自動生成が開始されます。",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

// ウィザード用スイッチ付き設定行
@Composable
private fun WizardSwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text = label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
