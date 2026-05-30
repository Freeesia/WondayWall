package com.studiofreesia.wondaywall.ui.screens.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.UpdateSchedule
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// 設定画面の UI 状態
data class SettingsUiState(
    val config: AppConfig = AppConfig(),
    val isSaving: Boolean = false,
    val errorMessage: String? = null,
)

// 設定画面の ViewModel
class SettingsViewModel(
    private val appConfigService: AppConfigService,
    private val taskSchedulerService: TaskSchedulerService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadConfig()
    }

    // 設定を読み込む
    fun loadConfig() {
        viewModelScope.launch {
            val config = appConfigService.getConfig()
            _uiState.value = _uiState.value.copy(config = config)
        }
    }

    // API キーを更新する
    fun updateApiKey(key: String) {
        updateConfigValue { it.copy(googleAiApiKey = key) }
    }

    // 自動生成の有効/無効を切り替える
    fun toggleAutoGeneration(enabled: Boolean) {
        viewModelScope.launch {
            appConfigService.updateConfig { it.copy(autoGenerationEnabled = enabled) }
            val config = appConfigService.getConfig()
            if (enabled) {
                taskSchedulerService.scheduleNext()
            } else if (!taskSchedulerService.isGenerationWorkRunning()) {
                taskSchedulerService.cancelScheduled()
            }
            _uiState.value = _uiState.value.copy(config = config)
        }
    }

    // スケジュールを更新する
    fun updateSchedule(newSchedule: UpdateSchedule) {
        viewModelScope.launch {
            appConfigService.updateConfig { config ->
                config.copy(schedule = newSchedule)
            }
            val config = appConfigService.getConfig()
            _uiState.value = _uiState.value.copy(config = config)
            // スケジュールを再登録する
            if (config.autoGenerationEnabled) {
                taskSchedulerService.scheduleNext()
            }
        }
    }

    // Wi-Fi のみ設定を切り替える
    fun toggleWifiOnly(enabled: Boolean) {
        viewModelScope.launch {
            appConfigService.updateConfig { it.copy(generateOnlyOnWifi = enabled) }
            val config = appConfigService.getConfig()
            _uiState.value = _uiState.value.copy(config = config)
            if (config.autoGenerationEnabled) {
                taskSchedulerService.scheduleNext()
            }
        }
    }

    // 省電力中スキップ設定を切り替える
    fun toggleSkipOnBatterySaver(enabled: Boolean) {
        updateConfigValue { it.copy(skipOnBatterySaver = enabled) }
    }

    // ロック画面更新設定を切り替える
    fun toggleUpdateLockScreen(enabled: Boolean) {
        updateConfigValue { it.copy(updateLockScreen = enabled) }
    }

    // 通知設定を切り替える
    fun toggleShowNotification(enabled: Boolean) {
        updateConfigValue { it.copy(showNotification = enabled) }
    }

    // 通知権限が拒否された場合は通知設定を保存しない
    fun onNotificationPermissionDenied() {
        viewModelScope.launch {
            appConfigService.updateConfig { it.copy(showNotification = false) }
            val config = appConfigService.getConfig()
            _uiState.value = _uiState.value.copy(
                config = config,
                errorMessage = "通知権限が許可されていないため、通知はオフにしました。",
            )
        }
    }

    // Flex ティア強制使用を切り替える
    fun toggleForceFlexTier(enabled: Boolean) {
        updateConfigValue { it.copy(forceFlexTier = enabled) }
    }

    // 設定値を更新してキャッシュも更新する汎用メソッド
    private fun updateConfigValue(update: (AppConfig) -> AppConfig) {
        viewModelScope.launch {
            appConfigService.updateConfig(update)
            val config = appConfigService.getConfig()
            _uiState.value = _uiState.value.copy(config = config)
        }
    }

    // エラーメッセージをクリアする
    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    companion object {
        fun factory(
            appConfigService: AppConfigService,
            taskSchedulerService: TaskSchedulerService,
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                SettingsViewModel(appConfigService, taskSchedulerService) as T
        }
    }
}
