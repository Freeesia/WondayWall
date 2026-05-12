package com.studiofreesia.wondaywall.models

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

// 画像生成 API に渡すカレンダーイベント（Gemini API プロンプト用）
@Serializable
data class PromptCalendarEvent(
    val id: String,
    val title: String,
    // イベントの近接タグ（"today" / "tomorrow" / "in N days"）
    val proximityTag: String,
    val startTime: Instant,
    val endTime: Instant?,
    val location: String?,
    val description: String?,
)

// 画像生成 API に渡すニューストピック（Gemini API プロンプト用）
@Serializable
data class PromptNewsTopic(
    val id: String,
    val title: String,
    val summary: String?,
    val url: String?,
    val publishedAt: Instant?,
    val ogpImageUrl: String?,
)

// 画像生成に渡すコンテキスト一式
data class PromptContext(
    // カレンダーイベント候補（7日以内の今後の予定）
    val calendarEvents: List<PromptCalendarEvent> = emptyList(),
    // ニューストピック候補（最大10件）
    val newsTopics: List<PromptNewsTopic> = emptyList(),
    // 画像サイズ（"2K"）
    val imageSize: String = "2K",
    // アスペクト比（Android向け縦長 "9:16"）
    val aspectRatio: String = "9:16",
    // ユーザーの追加制約・プロンプト
    val additionalConstraints: String = "",
    // ベース壁紙のファイルパス（前回画像をベースにする場合）
    val baseImagePath: String? = null,
)

// コンテキスト構築の結果
data class ContextBuildResult(
    val promptContext: PromptContext,
    val calendarEvents: List<CalendarEventItem>,
    val newsTopics: List<NewsTopicItem>,
)
