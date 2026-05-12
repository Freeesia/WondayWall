package com.studiofreesia.wondaywall.models

// カレンダーソース情報（CalendarContract から取得したカレンダー一覧）
data class CalendarSourceItem(
    // CalendarContract の Calendars._ID
    val id: String,
    // カレンダーの表示名
    val displayName: String,
    // アカウント名
    val accountName: String,
    // カレンダーカラー（ARGB）
    val color: Int,
    // ユーザーが選択済みか
    val isSelected: Boolean = false,
)
