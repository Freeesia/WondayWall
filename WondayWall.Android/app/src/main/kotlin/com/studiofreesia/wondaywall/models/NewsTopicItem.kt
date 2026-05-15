package com.studiofreesia.wondaywall.models

import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable

// ニューストピック（RSS/フィードから取得した記事）
@Serializable
data class NewsTopicItem(
    // 一意ID（RSS の guid またはURL から生成）
    val id: String,
    // 記事タイトル
    val title: String,
    // 記事の概要
    val summary: String?,
    // 記事URL
    val url: String?,
    // 公開日時
    val publishedAt: Instant,
    // OGP画像URL（取得できた場合）
    val ogpImageUrl: String?,
)
