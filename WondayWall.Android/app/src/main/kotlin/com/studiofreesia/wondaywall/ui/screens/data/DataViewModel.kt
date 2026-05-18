package com.studiofreesia.wondaywall.ui.screens.data

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.CalendarSourceItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.ContextService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// データ画面の UI 状態
data class DataUiState(
    val hasCalendarPermission: Boolean = false,
    val calendarSources: List<CalendarSourceItem> = emptyList(),
    val calendarEvents: List<CalendarEventItem> = emptyList(),
    val rssSources: List<String> = emptyList(),
    val newsTopics: List<NewsTopicItem> = emptyList(),
    val userPrompt: String = "",
    val isLoadingNews: Boolean = false,
    val errorMessage: String? = null,
    val config: AppConfig = AppConfig(),
)

// データ画面の ViewModel
class DataViewModel(
    private val appConfigService: AppConfigService,
    private val contextService: ContextService,
) : ViewModel() {

    private val _uiState = MutableStateFlow(DataUiState())
    val uiState: StateFlow<DataUiState> = _uiState.asStateFlow()

    init {
        loadData()
    }

    // 画面データを読み込む
    fun loadData() {
        viewModelScope.launch {
            val config = appConfigService.getConfig()
            val hasPermission = contextService.hasCalendarPermission()

            // カレンダー一覧・予定を取得する
            val calendarSources = if (hasPermission) {
                contextService.getCalendarSources().map { source ->
                    source.copy(isSelected = config.targetCalendarIds.contains(source.id))
                }
            } else emptyList()

            val calendarEvents = if (hasPermission) {
                contextService.getCalendarEvents(config.targetCalendarIds)
            } else emptyList()

            _uiState.value = _uiState.value.copy(
                hasCalendarPermission = hasPermission,
                calendarSources = calendarSources,
                calendarEvents = calendarEvents,
                rssSources = config.rssSources,
                userPrompt = config.userPrompt,
                config = config,
            )

            // ニュースを非同期で読み込む
            loadNews(config.rssSources)
        }
    }

    // ニュースを取得する
    private suspend fun loadNews(rssSources: List<String>) {
        if (rssSources.isEmpty()) return
        _uiState.value = _uiState.value.copy(isLoadingNews = true)
        try {
            val result = contextService.buildPromptContext()
            _uiState.value = _uiState.value.copy(
                newsTopics = result.newsTopics,
                isLoadingNews = false,
            )
        } catch (e: Exception) {
            _uiState.value = _uiState.value.copy(
                isLoadingNews = false,
                errorMessage = "ニュースの取得に失敗しました: ${e.message}",
            )
        }
    }

    // カレンダーの選択状態を切り替える
    fun toggleCalendarSelection(calendarId: String) {
        viewModelScope.launch {
            val current = appConfigService.getConfig()
            val newIds = if (current.targetCalendarIds.contains(calendarId)) {
                current.targetCalendarIds - calendarId
            } else {
                current.targetCalendarIds + calendarId
            }
            appConfigService.updateConfig { it.copy(targetCalendarIds = newIds) }
            loadData()
        }
    }

    // RSS ソースを追加する
    fun addRssSource(url: String, onAdded: () -> Unit = {}) {
        if (url.isBlank()) return
        viewModelScope.launch {
            val sourceUrl = url.trim()
            val resolvedRssUrl = contextService.resolveRssSourceUrl(sourceUrl)
            if (resolvedRssUrl == null) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = "指定のサイトからニュース情報を得られませんでした。"
                )
                return@launch
            }

            var added = false
            appConfigService.updateConfig { config ->
                if (config.rssSources.contains(resolvedRssUrl)) config
                else {
                    added = true
                    config.copy(rssSources = config.rssSources + resolvedRssUrl)
                }
            }
            loadData()
            if (added) onAdded()
        }
    }

    // RSS ソースを削除する
    fun removeRssSource(url: String) {
        viewModelScope.launch {
            appConfigService.updateConfig { config ->
                config.copy(rssSources = config.rssSources - url)
            }
            loadData()
        }
    }

    // ユーザープロンプトを保存する
    fun saveUserPrompt(prompt: String) {
        viewModelScope.launch {
            appConfigService.updateConfig { it.copy(userPrompt = prompt) }
            _uiState.value = _uiState.value.copy(userPrompt = prompt)
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
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T =
                DataViewModel(appConfigService, contextService) as T
        }
    }
}
