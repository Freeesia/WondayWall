package com.studiofreesia.wondaywall.models

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

// カレンダーイベント（CalendarContract から取得した予定）
@Serializable
data class CalendarEventItem(
    // CalendarContract の _ID
    val id: String,
    // カレンダーID
    val calendarId: String,
    // 予定タイトル
    val title: String,
    // 開始時刻
    val startTime: Instant,
    // 終了時刻（終日予定では null の場合がある）
    val endTime: Instant?,
    // 終日予定か
    val isAllDay: Boolean,
    // 場所
    val location: String?,
    // メモ・本文
    val notes: String?,
)
