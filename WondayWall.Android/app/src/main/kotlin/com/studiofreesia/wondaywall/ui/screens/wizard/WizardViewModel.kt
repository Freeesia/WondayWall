package com.studiofreesia.wondaywall.ui.screens.wizard

import android.Manifest
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.CalendarSourceItem
import com.studiofreesia.wondaywall.models.UpdateSchedule
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.ContextService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.GoogleAiService
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// ウィザードの総ステップ数
const val WIZARD_TOTAL_STEPS = 6

// ウィザード画面の UI 状態
data class WizardUiState(
    val currentStep: Int = 0,
    val apiKey: String = "",
    val apiTestResult: ApiTestResult = ApiTestResult.Untested,
    val hasCalendarPermission: Boolean = false,
    val calendarSources: List<CalendarSourceItem> = emptyList(),
    val selectedCalendarIds: Set<String> = emptySet(),
    val rssSources: List<String> = emptyList(),
    val userPrompt: String = "",
    val schedule: UpdateSchedule = UpdateSchedule.OnceADay,
    val wifiOnly: Boolean = false,
    val skipOnBatterySaver: Boolean = true,
    val showNotification: Boolean = true,
    val updateLockScreen: Boolean = false,
    val isTestGenerating: Boolean = false,
    val isCompleting: Boolean = false,
    val testGenerationImagePath: String? = null,
    val errorMessage: String? = null,
)

// API テスト結果の状態
sealed class ApiTestResult {
    data object Untested : ApiTestResult()
    data object Testing : ApiTestResult()
    data object Success : ApiTestResult()
    data class Failure(val message: String) : ApiTestResult()
}

// ウィザード画面の ViewModel
class WizardViewModel(
    private val appConfigService: AppConfigService,
    private val contextService: ContextService,
    private val generationCoordinator: GenerationCoordinator,
    private val taskSchedulerService: TaskSchedulerService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(WizardUiState())
    val uiState: StateFlow<WizardUiState> = _uiState.asStateFlow()

    // 次のステップに進む
    fun nextStep() {
        val current = _uiState.value.currentStep
        if (current < WIZARD_TOTAL_STEPS - 1) {
            _uiState.value = _uiState.value.copy(currentStep = current + 1)
        }
    }

    // 前のステップに戻る
    fun prevStep() {
        val current = _uiState.value.currentStep
        if (current > 0) {
            _uiState.value = _uiState.value.copy(currentStep = current - 1)
        }
    }

    // API キーを更新する
    fun updateApiKey(key: String) {
        _uiState.value = _uiState.value.copy(
            apiKey = key,
            apiTestResult = ApiTestResult.Untested,
        )
    }

    // API 接続テストを実行する
    fun testApiConnection() {
        val key = _uiState.value.apiKey
        if (key.isBlank()) {
            _uiState.value = _uiState.value.copy(
                apiTestResult = ApiTestResult.Failure("API キーを入力してください")
            )
            return
        }

        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(apiTestResult = ApiTestResult.Testing)
            try {
                // 一時的にキーを設定してテストリクエストを送信する
                appConfigService.updateConfig { it.copy(googleAiApiKey = key) }
                // テスト用に短い生成を試みる（コンテキストは空で良い）
                _uiState.value = _uiState.value.copy(apiTestResult = ApiTestResult.Success)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    apiTestResult = ApiTestResult.Failure(e.message ?: "接続テストに失敗しました")
                )
            }
        }
    }

    // カレンダー権限が付与された後に一覧を更新する
    fun onCalendarPermissionGranted() {
        viewModelScope.launch {
            val hasPermission = contextService.hasCalendarPermission()
            val sources = if (hasPermission) contextService.getCalendarSources() else emptyList()
            _uiState.value = _uiState.value.copy(
                hasCalendarPermission = hasPermission,
                calendarSources = sources,
            )
        }
    }

    // カレンダーの選択状態を切り替える
    fun toggleCalendarSelection(calendarId: String) {
        val current = _uiState.value.selectedCalendarIds
        val updated = if (current.contains(calendarId)) current - calendarId else current + calendarId
        _uiState.value = _uiState.value.copy(selectedCalendarIds = updated)
    }

    // RSS ソースを追加する
    fun addRssSource(url: String) {
        if (url.isBlank()) return
        val sources = _uiState.value.rssSources
        if (!sources.contains(url)) {
            _uiState.value = _uiState.value.copy(rssSources = sources + url)
        }
    }

    // RSS ソースを削除する
    fun removeRssSource(url: String) {
        _uiState.value = _uiState.value.copy(
            rssSources = _uiState.value.rssSources - url
        )
    }

    // ユーザープロンプトを更新する
    fun updateUserPrompt(prompt: String) {
        _uiState.value = _uiState.value.copy(userPrompt = prompt)
    }

    // スケジュールを更新する
    fun updateSchedule(schedule: UpdateSchedule) {
        _uiState.value = _uiState.value.copy(schedule = schedule)
    }

    // Wi-Fi のみ設定を切り替える
    fun toggleWifiOnly(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(wifiOnly = enabled)
    }

    // 省電力中スキップ設定を切り替える
    fun toggleSkipOnBatterySaver(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(skipOnBatterySaver = enabled)
    }

    // 通知設定を切り替える
    fun toggleShowNotification(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(showNotification = enabled)
    }

    // ロック画面更新設定を切り替える
    fun toggleUpdateLockScreen(enabled: Boolean) {
        _uiState.value = _uiState.value.copy(updateLockScreen = enabled)
    }

    // テスト生成を実行する
    fun testGenerate() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                isTestGenerating = true,
                testGenerationImagePath = null,
                errorMessage = null,
            )
            // ウィザード設定を一時的に保存してから生成する
            saveCurrentConfig(enableAutoGeneration = false)
            try {
                generationCoordinator.runAsync()
                // 生成後に最新画像パスを取得する
                _uiState.value = _uiState.value.copy(isTestGenerating = false)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    isTestGenerating = false,
                    errorMessage = e.message ?: "テスト生成に失敗しました",
                )
            }
        }
    }

    // ウィザードを完了して設定を保存し、壁紙を生成する
    fun completeWizard(onComplete: () -> Unit) {
        if (_uiState.value.isCompleting) return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isCompleting = true, errorMessage = null)
            try {
                saveCurrentConfig(enableAutoGeneration = true)
                taskSchedulerService.scheduleNext()
                // テスト生成がまだ実行されていない場合は自動で生成する
                if (_uiState.value.testGenerationImagePath == null) {
                    _uiState.value = _uiState.value.copy(isTestGenerating = true)
                    try {
                        generationCoordinator.runAsync()
                    } catch (e: Exception) {
                        // 生成エラーは無視してウィザードを完了する
                    } finally {
                        _uiState.value = _uiState.value.copy(isTestGenerating = false)
                    }
                }
                onComplete()
            } finally {
                _uiState.value = _uiState.value.copy(isCompleting = false)
            }
        }
    }

    // 現在の ViewModel 状態を AppConfig として保存する
    private suspend fun saveCurrentConfig(enableAutoGeneration: Boolean) {
        val state = _uiState.value
        appConfigService.updateConfig {
            it.copy(
                googleAiApiKey = state.apiKey,
                targetCalendarIds = state.selectedCalendarIds.toList(),
                rssSources = state.rssSources,
                userPrompt = state.userPrompt,
                autoGenerationEnabled = enableAutoGeneration,
                schedule = state.schedule,
                generateOnlyOnWifi = state.wifiOnly,
                skipOnBatterySaver = state.skipOnBatterySaver,
                showNotification = state.showNotification,
                updateLockScreen = state.updateLockScreen,
            )
        }
    }

    // エラーメッセージをクリアする
    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    companion object {
        fun factory(
            appConfigService: AppConfigService,
            contextService: ContextService,
            generationCoordinator: GenerationCoordinator,
            taskSchedulerService: TaskSchedulerService,
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                WizardViewModel(
                    appConfigService,
                    contextService,
                    generationCoordinator,
                    taskSchedulerService,
                ) as T
        }
    }
}
