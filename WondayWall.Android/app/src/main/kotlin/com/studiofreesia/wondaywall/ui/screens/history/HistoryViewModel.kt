package com.studiofreesia.wondaywall.ui.screens.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.HistoryService
import com.studiofreesia.wondaywall.services.WallpaperService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// 履歴画面の UI 状態
data class HistoryUiState(
    val historyItems: List<HistoryItem> = emptyList(),
    val isGenerating: Boolean = false,
    val errorMessage: String? = null,
    val config: AppConfig = AppConfig(),
)

// 履歴画面の ViewModel
class HistoryViewModel(
    private val historyService: HistoryService,
    private val wallpaperService: WallpaperService,
    private val generationCoordinator: GenerationCoordinator,
    private val appConfigService: AppConfigService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(HistoryUiState())
    val uiState: StateFlow<HistoryUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            historyService.historyChanges.collect {
                refreshHistory()
            }
        }
        viewModelScope.launch {
            generationCoordinator.isGenerating.collect { generating ->
                _uiState.value = _uiState.value.copy(isGenerating = generating)
            }
        }
    }

    // 履歴を読み込む
    fun loadHistory() {
        viewModelScope.launch {
            refreshHistory()
        }
    }

    private suspend fun refreshHistory() {
        val history = historyService.loadHistory()
        val config = appConfigService.getConfig()
        _uiState.value = _uiState.value.copy(
            historyItems = history,
            config = config,
            errorMessage = null,
        )
    }

    // 履歴アイテムを削除する
    fun deleteItem(itemId: String) {
        viewModelScope.launch {
            historyService.deleteHistoryItem(itemId)
            loadHistory()
        }
    }

    // 壁紙を再適用する
    fun reapplyWallpaper(item: HistoryItem) {
        val imageReference = item.imageReference ?: return
        viewModelScope.launch {
            val config = appConfigService.getConfig()
            val result = wallpaperService.applyWallpaper(imageReference, config.updateLockScreen)
            if (result.isFailure) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = "壁紙の適用に失敗しました: ${result.exceptionOrNull()?.message}"
                )
            }
        }
    }

    // 画像共有 Intent を取得する（Activity から startActivity で使用する）
    fun buildShareIntent(item: HistoryItem) =
        item.imageReference?.let { wallpaperService.buildShareIntent(it) }

    // エラーメッセージをクリアする
    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    companion object {
        fun factory(
            historyService: HistoryService,
            wallpaperService: WallpaperService,
            generationCoordinator: GenerationCoordinator,
            appConfigService: AppConfigService,
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                HistoryViewModel(
                    historyService,
                    wallpaperService,
                    generationCoordinator,
                    appConfigService,
                ) as T
        }
    }
}
