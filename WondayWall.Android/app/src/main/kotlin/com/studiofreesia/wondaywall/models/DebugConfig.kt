package com.studiofreesia.wondaywall.models

import kotlinx.serialization.Serializable

// デバッグ専用設定モデル
@Serializable
data class DebugConfig(
    // ダミーAIサービスに切り替える（切り替えは次回起動時に反映）
    val useDummyAiService: Boolean = false,
    // ダミー実装でのプロンプト生成遅延秒数
    val dummyPromptDelaySeconds: Int = 180,
    // ダミー実装での画像生成遅延秒数
    val dummyImageDelaySeconds: Int = 600,
    // ダミー実装で生成コンテキストに含めるニュース件数
    val dummyNewsCount: Int = 4,
) {
    fun normalized(): DebugConfig = copy(
        dummyPromptDelaySeconds = dummyPromptDelaySeconds.coerceIn(MIN_DELAY_SECONDS, MAX_DELAY_SECONDS),
        dummyImageDelaySeconds = dummyImageDelaySeconds.coerceIn(MIN_DELAY_SECONDS, MAX_DELAY_SECONDS),
        dummyNewsCount = dummyNewsCount.coerceIn(MIN_NEWS_COUNT, MAX_NEWS_COUNT),
    )

    companion object {
        const val MIN_DELAY_SECONDS = 1
        const val MAX_DELAY_SECONDS = 3600
        const val MIN_NEWS_COUNT = 0
        const val MAX_NEWS_COUNT = 20
    }
}
