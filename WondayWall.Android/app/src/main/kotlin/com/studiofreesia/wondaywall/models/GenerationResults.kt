package com.studiofreesia.wondaywall.models

// テキストモデルで生成した画像プロンプト
data class PromptGenerationResult(
    val imagePrompt: String,
    val selectedNewsIds: List<String>,
    val usedNewsTopics: List<NewsTopicItem>? = null,
)

// 画像モデルで生成し、保存した壁紙画像
data class GeneratedImageResult(
    val temporaryFilePath: String,
    val imagePrompt: String,
)
