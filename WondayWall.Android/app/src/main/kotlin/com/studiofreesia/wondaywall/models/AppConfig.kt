package com.studiofreesia.wondaywall.models

import kotlinx.serialization.Serializable

// アプリ設定モデル（Windows版 AppConfig と同名フィールドで揃える）
@Serializable
data class AppConfig(
    // Google AI APIキー
    val googleAiApiKey: String = "",
    // 取得対象カレンダーID一覧（Calendar ProviderのカレンダーID）
    val targetCalendarIds: List<String> = emptyList(),
    // RSSソースURL一覧
    val rssSources: List<String> = emptyList(),
    // ユーザーの追加プロンプト・制約
    val userPrompt: String = "",
    // 自動更新スケジュール（Windows版 AppConfig.Schedule と同名）
    val schedule: UpdateSchedule = UpdateSchedule.OnceADay,
    // 生成材料に変化がなければスキップするか
    val skipGenerationWhenNoChanges: Boolean = false,
    // ロック画面も更新するか（false = ホーム画面のみ）
    val updateLockScreen: Boolean = false,

    // Android固有設定
    // 自動生成を有効にするか
    val autoGenerationEnabled: Boolean = false,
    // 生成時に通知するか（成功・失敗ともに同一フラグで管理）
    val showNotification: Boolean = true,
    // Wi-Fi接続時のみ生成するか
    val generateOnlyOnWifi: Boolean = false,
    // 省電力モード時は生成をスキップするか
    val skipOnBatterySaver: Boolean = true,
    // 手動生成でも Flex ティアを強制使用する
    val forceFlexTier: Boolean = false,
)
