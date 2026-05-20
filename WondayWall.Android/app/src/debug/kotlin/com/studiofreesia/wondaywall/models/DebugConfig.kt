package com.studiofreesia.wondaywall.models

import kotlinx.serialization.Serializable

// デバッグ専用設定モデル
@Serializable
data class DebugConfig(
    // Google AI をダミー実装に切り替える（切り替えは次回起動時に反映）
    val useDummyGoogleAiService: Boolean = false,
    // ダミー実装でのプロンプト生成遅延秒数
    val dummyPromptDelaySeconds: Int = 180,
    // ダミー実装での画像生成遅延秒数
    val dummyImageDelaySeconds: Int = 600,
) {
    fun normalized(): DebugConfig = copy(
        dummyPromptDelaySeconds = dummyPromptDelaySeconds.coerceIn(MIN_DELAY_SECONDS, MAX_DELAY_SECONDS),
        dummyImageDelaySeconds = dummyImageDelaySeconds.coerceIn(MIN_DELAY_SECONDS, MAX_DELAY_SECONDS),
    )

    companion object {
        const val MIN_DELAY_SECONDS = 1
        const val MAX_DELAY_SECONDS = 3600
    }
}
