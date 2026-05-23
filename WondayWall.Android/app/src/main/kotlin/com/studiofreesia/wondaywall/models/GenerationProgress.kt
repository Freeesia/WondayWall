package com.studiofreesia.wondaywall.models

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// 生成を開始した入口
@Serializable
enum class GenerationTrigger {
    @SerialName("manual")
    Manual,

    @SerialName("scheduled")
    Scheduled,

    @SerialName("startup_recovery")
    StartupRecovery,
}

// UI と Foreground 通知に表示する生成フェーズ
@Serializable
enum class GenerationPhase {
    @SerialName("queued")
    Queued,

    @SerialName("starting")
    Starting,

    @SerialName("building_context")
    BuildingContext,

    @SerialName("generating_prompt")
    GeneratingPrompt,

    @SerialName("fetching_ogp")
    FetchingOgp,

    @SerialName("requesting_image")
    RequestingImage,

    @SerialName("saving_image")
    SavingImage,

    @SerialName("applying_wallpaper")
    ApplyingWallpaper,

    @SerialName("completed")
    Completed,

    @SerialName("skipped")
    Skipped,

    @SerialName("failed")
    Failed,

    @SerialName("rejected")
    Rejected,
}

// 生成進捗。WorkManager progress、通知、UI の共通データとして扱う。
@Serializable
data class GenerationProgress(
    val percent: Int,
    val message: String,
    val phase: GenerationPhase,
    val historyId: String? = null,
    val trigger: GenerationTrigger,
)
