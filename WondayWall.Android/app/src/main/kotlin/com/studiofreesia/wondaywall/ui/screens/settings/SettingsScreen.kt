package com.studiofreesia.wondaywall.ui.screens.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp

import com.studiofreesia.wondaywall.models.UpdateSchedule

// 設定画面
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel,
    onNavigateToAbout: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    var apiKeyText by remember { mutableStateOf(uiState.config.googleAiApiKey) }
    var scheduleDropdownExpanded by remember { mutableStateOf(false) }

    LaunchedEffect(uiState.config.googleAiApiKey) {
        if (apiKeyText != uiState.config.googleAiApiKey) {
            apiKeyText = uiState.config.googleAiApiKey
        }
    }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let {
            snackbarHostState.showSnackbar(it)
            viewModel.clearError()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("設定") },
                actions = {
                    IconButton(onClick = onNavigateToAbout) {
                        Icon(Icons.Default.Info, contentDescription = "アプリについて")
                    }
                },
            )
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

            // ─── API キーセクション ───
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.Key, contentDescription = null)
                        Text("Google AI API キー", style = MaterialTheme.typography.titleMedium)
                    }
                    Spacer(Modifier.height(8.dp))
                    OutlinedTextField(
                        value = apiKeyText,
                        onValueChange = { apiKeyText = it },
                        modifier = Modifier
                            .fillMaxWidth()
                            // フォーカスを失ったときのみ保存する（毎キーストロークの DataStore 書き込みを防ぐ）
                            .onFocusChanged { focusState ->
                                if (!focusState.isFocused && apiKeyText != uiState.config.googleAiApiKey) {
                                    viewModel.updateApiKey(apiKeyText)
                                }
                            },
                        label = { Text("API キー") },
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                        singleLine = true,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = "入力後にフォーカスを外すと自動保存されます",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // ─── 自動生成スケジュールセクション ───
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.Schedule, contentDescription = null)
                        Text("自動生成スケジュール", style = MaterialTheme.typography.titleMedium)
                    }
                    Spacer(Modifier.height(8.dp))

                    // 自動生成 ON/OFF
                    SwitchRow(
                        label = "自動生成を有効にする",
                        checked = uiState.config.autoGenerationEnabled,
                        onCheckedChange = viewModel::toggleAutoGeneration,
                    )

                    // スケジュールドロップダウン
                    if (uiState.config.autoGenerationEnabled) {
                        Spacer(Modifier.height(8.dp))
                        ExposedDropdownMenuBox(
                            expanded = scheduleDropdownExpanded,
                            onExpandedChange = { scheduleDropdownExpanded = it },
                        ) {
                            OutlinedTextField(
                                value = uiState.config.schedule.displayName(),
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
                    }
                }
            }

            // ─── 動作設定セクション ───
            ElevatedCard(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Icon(Icons.Default.Tune, contentDescription = null)
                        Text("動作設定", style = MaterialTheme.typography.titleMedium)
                    }
                    Spacer(Modifier.height(8.dp))

                    SwitchRow(
                        label = "Wi-Fi 接続時のみ生成する",
                        checked = uiState.config.generateOnlyOnWifi,
                        onCheckedChange = viewModel::toggleWifiOnly,
                    )
                    SwitchRow(
                        label = "省電力モード中はスキップする",
                        checked = uiState.config.skipOnBatterySaver,
                        onCheckedChange = viewModel::toggleSkipOnBatterySaver,
                    )
                    SwitchRow(
                        label = "ロック画面も更新する",
                        checked = uiState.config.updateLockScreen,
                        onCheckedChange = viewModel::toggleUpdateLockScreen,
                    )
                    SwitchRow(
                        label = "通知を表示する",
                        checked = uiState.config.showNotification,
                        onCheckedChange = viewModel::toggleShowNotification,
                    )
                    SwitchRow(
                        label = "Flex ティアを強制使用する",
                        checked = uiState.config.forceFlexTier,
                        onCheckedChange = viewModel::toggleForceFlexTier,
                    )
                }
            }
        }
    }
}

// スイッチ付き設定行
@Composable
private fun SwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            modifier = Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
        )
    }
}
