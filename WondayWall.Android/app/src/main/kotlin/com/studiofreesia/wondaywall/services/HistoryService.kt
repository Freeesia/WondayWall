package com.studiofreesia.wondaywall.services

import android.content.Context
import android.util.Log
import com.studiofreesia.wondaywall.models.HistoryItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
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

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    // 履歴一覧を読み込む（新しい順）
    suspend fun loadHistory(): List<HistoryItem> = withContext(Dispatchers.IO) {
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
    private suspend fun saveHistory(items: List<HistoryItem>): Boolean = withContext(Dispatchers.IO) {
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
    suspend fun addHistoryItem(item: HistoryItem): Boolean {
        val existing = loadHistory().toMutableList()
        existing.add(0, item)
        val saved = saveHistory(existing.take(100))
        if (saved) {
            _historyChanges.update { it + 1 }
        }
        return saved
    }

    // 最新の成功履歴を取得する
    suspend fun getLatestSuccessItem(): HistoryItem? =
        loadHistory().firstOrNull { it.isSuccess && !it.isSkipped }

    // 指定IDの履歴を削除する
    suspend fun deleteHistoryItem(id: String): Boolean {
        val existing = loadHistory().filter { it.id != id }
        val saved = saveHistory(existing)
        if (saved) {
            _historyChanges.update { it + 1 }
        }
        return saved
    }

    // 最後に成功した生成時刻をエポックミリ秒で取得する（スロット判定用）
    suspend fun getLastSuccessTimeMillis(): Long? {
        val item = getLatestSuccessItem() ?: return null
        return item.executedAt.toEpochMilliseconds()
    }

    companion object {
        private const val TAG = "HistoryService"
    }
}
