package com.studiofreesia.wondaywall.models

import kotlinx.serialization.Serializable

// 壁紙の自動更新スケジュール（Windows版 UpdateSchedule と同名で揃える）
@Serializable
enum class UpdateSchedule {
    // 週1回（月曜 4:00）
    OnceAWeek,
    // 週2回（月曜・木曜 4:00）
    TwiceAWeek,
    // 週3回（月曜・水曜・金曜 4:00）
    ThreeTimesAWeek,
    // 1日1回（4:00）
    OnceADay,
    // 1日3回（朝4:00・昼12:00・晩18:00）
    ThreeTimesADay,
    ;

    // 画面表示用の日本語名
    fun displayName(): String = when (this) {
        OnceAWeek -> "週1回"
        TwiceAWeek -> "週2回"
        ThreeTimesAWeek -> "週3回"
        OnceADay -> "1日1回"
        ThreeTimesADay -> "1日3回"
    }
}
