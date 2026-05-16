package com.studiofreesia.wondaywall.models

import kotlinx.serialization.Serializable

// Google AI サービスティア（Windows版・iOS版と同名で揃える）
@Serializable
enum class GoogleAiServiceTier {
    // 通常の推論（手動生成時はこちらを使う）
    Standard,
    // コスト効率重視のバックグラウンド推論（容量不足時は Standard にフォールバック）
    Flex,
}
