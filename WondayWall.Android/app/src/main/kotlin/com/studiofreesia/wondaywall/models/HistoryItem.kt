package com.studiofreesia.wondaywall.models

import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.util.UUID

// 生成状態。生成中の中間状態も履歴に保存し、プロセス中断後の復旧判定に使う。
@Serializable
enum class GenerationStatus {
    @SerialName("generating")
    Generating,

    @SerialName("generating_prompt_ready")
    GeneratingPromptReady,

    @SerialName("generating_image_requested")
    GeneratingImageRequested,

    @SerialName("success")
    Success,

    @SerialName("skipped")
    Skipped,

    @SerialName("failure")
    Failure,
}

// 生成履歴の1件
@Serializable
data class HistoryItem(
    // 一意ID
    val id: String = UUID.randomUUID().toString(),
    // 実行日時
    val executedAt: Instant,
    // 生成状態
    val status: GenerationStatus,
    // エラー概要（失敗時のみ）
    val errorSummary: String? = null,
    // 写真領域に保存した画像 URI
    val appliedImageUri: String? = null,
    // 生成に使用したカレンダーイベント
    val usedCalendarEvents: List<CalendarEventItem>? = null,
    // 生成に使用したニューストピック
    val usedNewsTopics: List<NewsTopicItem>? = null,
    // 使用したサービスティア
    val serviceTier: GoogleAiServiceTier,
    // 生成に使用したユーザープロンプト（Android固有）
    val usedPrompt: String? = null,
    // テキストモデルが生成した画像プロンプト（再開用）
    val generatedPrompt: String? = null,
) {
    val isSuccess: Boolean
        get() = status == GenerationStatus.Success

    val isSkipped: Boolean
        get() = status == GenerationStatus.Skipped

    val isGenerating: Boolean
        get() = when (status) {
            GenerationStatus.Generating,
            GenerationStatus.GeneratingPromptReady,
            GenerationStatus.GeneratingImageRequested,
            -> true
            GenerationStatus.Success,
            GenerationStatus.Skipped,
            GenerationStatus.Failure,
            -> false
        }

}
