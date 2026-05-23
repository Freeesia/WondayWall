package com.studiofreesia.wondaywall.services

import android.content.Context
import android.util.Log
import com.studiofreesia.wondaywall.models.GenerationStatus
import com.studiofreesia.wondaywall.models.HistoryItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

// 生成履歴の読み書きを担当するサービス
// 履歴は context.filesDir/history.json に JSON 形式で保存する
class HistoryService(context: Context) {

    private val historyFile = File(context.filesDir, "history.json")
    private val _historyChanges = MutableStateFlow(0L)
    val historyChanges: StateFlow<Long> = _historyChanges.asStateFlow()
    private val fileMutex = Mutex()

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    init {
        recoverInterruptedHistoriesBlocking()
    }

    // 履歴一覧を読み込む（新しい順）
    suspend fun loadHistory(): List<HistoryItem> = fileMutex.withLock {
        loadHistoryUnlocked()
    }

    private suspend fun loadHistoryUnlocked(): List<HistoryItem> = withContext(Dispatchers.IO) {
        if (!historyFile.exists()) return@withContext emptyList()
        try {
            val text = historyFile.readText()
            json.decodeFromString<List<HistoryItem>>(text)
        } catch (e: Exception) {
            Log.e(TAG, "履歴の読み込みに失敗しました", e)
            emptyList()
        }
    }

    // 履歴一覧を保存する
    private suspend fun saveHistoryUnlocked(items: List<HistoryItem>): Boolean = withContext(Dispatchers.IO) {
        try {
            val text = json.encodeToString(items)
            historyFile.writeText(text)
            true
        } catch (e: Exception) {
            Log.e(TAG, "履歴の保存に失敗しました", e)
            false
        }
    }

    // 履歴に1件追加する（先頭に追加、最大100件）
    suspend fun addHistoryItem(item: HistoryItem): Boolean = fileMutex.withLock {
        val existing = loadHistoryUnlocked().toMutableList()
        existing.removeAll { it.id == item.id }
        existing.add(0, item)
        val saved = saveHistoryUnlocked(existing.take(MAX_ITEMS))
        if (saved) {
            _historyChanges.update { it + 1 }
        }
        saved
    }

    // 指定IDの履歴を更新する。存在しなければ先頭へ追加する。
    suspend fun updateHistoryItem(item: HistoryItem): Boolean = fileMutex.withLock {
        val existing = loadHistoryUnlocked().toMutableList()
        val index = existing.indexOfFirst { it.id == item.id }
        if (index >= 0) {
            existing[index] = item
        } else {
            existing.add(0, item)
        }
        val saved = saveHistoryUnlocked(existing.take(MAX_ITEMS))
        if (saved) {
            _historyChanges.update { it + 1 }
        }
        saved
    }

    // 最新の成功履歴を取得する
    suspend fun getLatestSuccessItem(): HistoryItem? =
        loadHistory().firstOrNull { it.isSuccess && !it.isSkipped }

    // 指定IDの履歴を取得する
    suspend fun getHistoryItem(id: String): HistoryItem? =
        loadHistory().firstOrNull { it.id == id }

    // 最後に完了した生成試行を取得する（成功・失敗・スキップをスロット消費済みとして扱う）
    suspend fun getLastCompletedRun(): HistoryItem? =
        loadHistory().firstOrNull { !it.isGenerating }

    // プロンプト生成前の未完了履歴を取得する
    suspend fun getPendingGeneratingItem(): HistoryItem? =
        loadHistory().firstOrNull { it.status == GenerationStatus.Generating }

    // プロンプト生成済み・画像API未呼び出しの未完了履歴を取得する
    suspend fun getGeneratingWithPrompt(): HistoryItem? =
        loadHistory().firstOrNull { it.status == GenerationStatus.GeneratingPromptReady }

    // 生成中の未完了履歴を取得する
    suspend fun getUnfinishedGeneratingItem(): HistoryItem? =
        loadHistory().firstOrNull { it.isGenerating }

    // 指定IDの履歴を削除する
    suspend fun deleteHistoryItem(id: String): Boolean = fileMutex.withLock {
        val existing = loadHistoryUnlocked().filter { it.id != id }
        val saved = saveHistoryUnlocked(existing)
        if (saved) {
            _historyChanges.update { it + 1 }
        }
        saved
    }

    // 最後に成功した生成時刻をエポックミリ秒で取得する（スロット判定用）
    suspend fun getLastSuccessTimeMillis(): Long? {
        val item = getLatestSuccessItem() ?: return null
        return item.executedAt.toEpochMilliseconds()
    }

    // 最後に完了した生成試行の時刻をエポックミリ秒で取得する（スロット判定用）
    suspend fun getLastCompletedRunTimeMillis(): Long? {
        val item = getLastCompletedRun() ?: return null
        return item.executedAt.toEpochMilliseconds()
    }

    // 画像API呼び出し済みのまま残った履歴は再開できないため、起動時に失敗へ変換する。
    private fun recoverInterruptedHistoriesBlocking() {
        if (!historyFile.exists()) return
        try {
            val history = json.decodeFromString<List<HistoryItem>>(historyFile.readText())
            var changed = false
            val recovered = history.map { item ->
                if (item.status == GenerationStatus.GeneratingImageRequested) {
                    changed = true
                    item.copy(
                        status = GenerationStatus.Failure,
                        errorSummary = item.errorSummary ?: "アプリが強制終了したため生成が中断されました",
                    )
                } else {
                    item
                }
            }
            if (changed) {
                historyFile.writeText(json.encodeToString(recovered))
                _historyChanges.value = _historyChanges.value + 1
            }
        } catch (e: Exception) {
            Log.e(TAG, "中断履歴の復旧に失敗しました", e)
        }
    }

    companion object {
        private const val TAG = "HistoryService"
        private const val MAX_ITEMS = 100
    }
}
