package com.studiofreesia.wondaywall.services

import android.content.Context
import com.studiofreesia.wondaywall.models.HistoryItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File

// 生成履歴の読み書きを担当するサービス
// 履歴は context.filesDir/history.json に JSON 形式で保存する
class HistoryService(context: Context) {

    private val historyFile = File(context.filesDir, "history.json")

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
            emptyList()
        }
    }

    // 履歴一覧を保存する
    private suspend fun saveHistory(items: List<HistoryItem>) = withContext(Dispatchers.IO) {
        try {
            val text = json.encodeToString(items)
            historyFile.writeText(text)
        } catch (e: Exception) {
            // 保存エラーは無視する
        }
    }

    // 履歴に1件追加する（先頭に追加、最大100件）
    suspend fun addHistoryItem(item: HistoryItem) {
        val existing = loadHistory().toMutableList()
        existing.add(0, item)
        saveHistory(existing.take(100))
    }

    // 最新の成功履歴を取得する
    suspend fun getLatestSuccessItem(): HistoryItem? =
        loadHistory().firstOrNull { it.isSuccess && !it.isSkipped }

    // 指定IDの履歴を削除する
    suspend fun deleteHistoryItem(id: String) {
        val existing = loadHistory().filter { it.id != id }
        saveHistory(existing)
    }

    // 最後に成功した生成時刻をエポックミリ秒で取得する（スロット判定用）
    suspend fun getLastSuccessTimeMillis(): Long? {
        val item = getLatestSuccessItem() ?: return null
        return item.executedAt.toEpochMilliseconds()
    }
}
