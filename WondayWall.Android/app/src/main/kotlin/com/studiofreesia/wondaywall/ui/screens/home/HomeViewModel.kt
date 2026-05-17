package com.studiofreesia.wondaywall.ui.screens.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.ContextService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.HistoryService
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import com.studiofreesia.wondaywall.services.WallpaperService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// ホーム画面の UI 状態
data class HomeUiState(
    val latestHistoryItem: HistoryItem? = null,
    val isGenerating: Boolean = false,
    val errorMessage: String? = null,
    val nextScheduledTime: String? = null,
    val config: AppConfig = AppConfig(),
    // 壁紙生成確認シートの表示フラグ
    val showGenerationSheet: Boolean = false,
    // 確認シートに表示するカレンダー予定
    val sheetEvents: List<CalendarEventItem> = emptyList(),
    // 確認シートに表示するニュース
    val sheetNews: List<NewsTopicItem> = emptyList(),
    // シートデータ読み込み中フラグ
    val isLoadingSheetData: Boolean = false,
)

// ホーム画面の ViewModel
class HomeViewModel(
    private val appConfigService: AppConfigService,
    private val generationCoordinator: GenerationCoordinator,
    private val historyService: HistoryService,
    private val wallpaperService: WallpaperService,
    private val taskSchedulerService: TaskSchedulerService,
    private val contextService: ContextService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            historyService.historyChanges.collect {
                refreshData()
            }
        }
        // 生成中フラグを監視する
        viewModelScope.launch {
            generationCoordinator.isGenerating.collect { isGenerating ->
                _uiState.value = _uiState.value.copy(isGenerating = isGenerating)
            }
        }
    }

    // 画面データを読み込む
    fun loadData() {
        viewModelScope.launch {
            refreshData()
        }
    }

    private suspend fun refreshData() {
        val history = historyService.loadHistory()
        val config = appConfigService.getConfig()
        _uiState.value = _uiState.value.copy(
            latestHistoryItem = history.firstOrNull { !it.isSkipped },
            config = config,
            errorMessage = null,
        )
    }

    // 壁紙生成確認シートを開く
    fun openGenerationSheet() {
        _uiState.value = _uiState.value.copy(
            showGenerationSheet = true,
            sheetEvents = emptyList(),
            sheetNews = emptyList(),
            isLoadingSheetData = true,
        )
        viewModelScope.launch {
            try {
                val result = contextService.buildPromptContext()
                _uiState.value = _uiState.value.copy(
                    sheetEvents = result.calendarEvents,
                    sheetNews = result.newsTopics,
                    isLoadingSheetData = false,
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingSheetData = false)
            }
        }
    }

    // 壁紙生成確認シートを閉じる
    fun dismissGenerationSheet() {
        _uiState.value = _uiState.value.copy(showGenerationSheet = false)
    }

    // 確認シートから生成を実行する
    fun generateFromSheet() {
        _uiState.value = _uiState.value.copy(showGenerationSheet = false)
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(errorMessage = null)
            try {
                generationCoordinator.runAsync()
                loadData()
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = e.message ?: "生成に失敗しました"
                )
            }
        }
    }

    // エラーメッセージをクリアする
    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    companion object {
        fun factory(
            appConfigService: AppConfigService,
            generationCoordinator: GenerationCoordinator,
            historyService: HistoryService,
            wallpaperService: WallpaperService,
            taskSchedulerService: TaskSchedulerService,
            contextService: ContextService,
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                HomeViewModel(
                    appConfigService,
                    generationCoordinator,
                    historyService,
                    wallpaperService,
                    taskSchedulerService,
                    contextService,
                ) as T
        }
    }
}

// ホーム画面の ViewModel
class HomeViewModel(
    private val appConfigService: AppConfigService,
    private val generationCoordinator: GenerationCoordinator,
    private val historyService: HistoryService,
    private val wallpaperService: WallpaperService,
    private val taskSchedulerService: TaskSchedulerService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            historyService.historyChanges.collect {
                refreshData()
            }
        }
        // 生成中フラグを監視する
        viewModelScope.launch {
            generationCoordinator.isGenerating.collect { isGenerating ->
                _uiState.value = _uiState.value.copy(isGenerating = isGenerating)
            }
        }
    }

    // 画面データを読み込む
    fun loadData() {
        viewModelScope.launch {
            refreshData()
        }
    }

    private suspend fun refreshData() {
        val history = historyService.loadHistory()
        val config = appConfigService.getConfig()
        _uiState.value = _uiState.value.copy(
            latestHistoryItem = history.firstOrNull { !it.isSkipped },
            config = config,
            errorMessage = null,
        )
    }

    // 今すぐ生成を実行する
    fun generateNow() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(errorMessage = null)
            try {
                generationCoordinator.runAsync()
                loadData()
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = e.message ?: "生成に失敗しました"
                )
            }
        }
    }

    // 画像を壁紙に適用する
    fun applyWallpaper(filePath: String) {
        viewModelScope.launch {
            val config = appConfigService.getConfig()
            val result = wallpaperService.applyWallpaper(filePath, config.updateLockScreen)
            if (result.isFailure) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = "壁紙の適用に失敗しました: ${result.exceptionOrNull()?.message}"
                )
            } else {
                loadData()
            }
        }
    }

    // 画像をギャラリーに保存する
    fun saveToGallery(filePath: String, onResult: (Boolean) -> Unit) {
        viewModelScope.launch {
            val result = wallpaperService.saveToGallery(filePath)
            onResult(result.isSuccess)
        }
    }

    // 画像共有 Intent を取得する（Activity から startActivity で使用する）
    fun buildShareIntent(filePath: String) = wallpaperService.buildShareIntent(filePath)

    // エラーメッセージをクリアする
    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    companion object {
        fun factory(
            appConfigService: AppConfigService,
            generationCoordinator: GenerationCoordinator,
            historyService: HistoryService,
            wallpaperService: WallpaperService,
            taskSchedulerService: TaskSchedulerService,
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                HomeViewModel(
                    appConfigService,
                    generationCoordinator,
                    historyService,
                    wallpaperService,
                    taskSchedulerService,
                ) as T
        }
    }
}
