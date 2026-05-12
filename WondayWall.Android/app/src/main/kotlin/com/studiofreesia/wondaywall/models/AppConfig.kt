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
    // 1日あたりの自動生成回数（1/2/3/4/6/8/12/24）
    val runsPerDay: Int = 1,
    // 前回生成画像をベースにするか
    val useCurrentWallpaperAsBase: Boolean = false,
    // 生成材料に変化がなければスキップするか
    val skipGenerationWhenNoChanges: Boolean = false,
    // ロック画面も更新するか（false = ホーム画面のみ）
    val updateLockScreen: Boolean = false,

    // Android固有設定
    // 自動生成を有効にするか
    val autoGenerationEnabled: Boolean = false,
    // 生成画像をギャラリーにも保存するか
    val saveToGallery: Boolean = false,
    // 生成成功時に通知するか
    val notifyOnSuccess: Boolean = true,
    // 生成失敗時に通知するか
    val notifyOnFailure: Boolean = true,
    // Wi-Fi接続時のみ生成するか
    val generateOnlyOnWifi: Boolean = false,
    // 省電力モード時は生成をスキップするか
    val skipOnBatterySaver: Boolean = true,

    // 初回セットアップウィザードが完了しているか
    val isSetupCompleted: Boolean = false,
)
