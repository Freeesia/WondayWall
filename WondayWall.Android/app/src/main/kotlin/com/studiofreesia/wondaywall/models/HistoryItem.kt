package com.studiofreesia.wondaywall.models

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable
import java.util.UUID

// 生成履歴の1件（Windows版 HistoryItem と同名フィールドで揃える）
@Serializable
data class HistoryItem(
    // 一意ID
    val id: String = UUID.randomUUID().toString(),
    // 実行日時
    val executedAt: Instant,
    // 生成成功か
    val isSuccess: Boolean,
    // エラー概要（失敗時のみ）
    val errorSummary: String?,
    // 適用した画像のファイルパス（成功時のみ）
    val appliedImagePath: String?,
    // 生成に使用したカレンダーイベント
    val usedCalendarEvents: List<CalendarEventItem>?,
    // 生成に使用したニューストピック
    val usedNewsTopics: List<NewsTopicItem>?,
    // 使用したサービスティア
    val serviceTier: GoogleAiServiceTier,
    // スキップされたか
    val isSkipped: Boolean = false,
    // 生成に使用したユーザープロンプト（Android固有）
    val usedPrompt: String? = null,
)
