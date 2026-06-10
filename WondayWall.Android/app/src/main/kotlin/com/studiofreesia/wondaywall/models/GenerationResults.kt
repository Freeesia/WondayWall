package com.studiofreesia.wondaywall.models

// テキストモデルで生成した画像プロンプト
data class PromptGenerationResult(
    val imagePrompt: String,
    val selectedNews: PromptSelectedNews = PromptSelectedNews.Ids(emptyList()),
)

// プロンプト生成で採用したニュース。ID参照か実体のどちらか一方だけを保持する。
sealed interface PromptSelectedNews {
    fun ids(): List<String>
    fun resolve(candidates: List<NewsTopicItem>): List<NewsTopicItem>

    data class Ids(val values: List<String>) : PromptSelectedNews {
        override fun ids(): List<String> = values
        override fun resolve(candidates: List<NewsTopicItem>): List<NewsTopicItem> =
            candidates.filter { values.contains(it.id) }
    }

    data class Items(val values: List<NewsTopicItem>) : PromptSelectedNews {
        override fun ids(): List<String> = values.map { it.id }
        override fun resolve(candidates: List<NewsTopicItem>): List<NewsTopicItem> = values
    }
}

// 画像モデルで生成し、保存した壁紙画像
data class GeneratedImageResult(
    val temporaryFilePath: String,
    val imagePrompt: String,
)
