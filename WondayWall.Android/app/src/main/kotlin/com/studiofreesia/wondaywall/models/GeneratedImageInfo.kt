package com.studiofreesia.wondaywall.models

// 生成画像の情報（GoogleAiService の生成結果）
data class GeneratedImageInfo(
    // 保存先ファイルパス
    val filePath: String,
    // 画像生成に使用したプロンプト
    val imagePrompt: String,
    // テキストモデルが採用したニュースIDの一覧
    val selectedNewsIds: List<String>,
)

// テキストモデルで生成した画像プロンプト
data class PromptGenerationResult(
    val imagePrompt: String,
    val selectedNewsIds: List<String>,
)

// 画像モデルで生成し、保存した壁紙画像
data class GeneratedImageResult(
    val filePath: String,
    val imagePrompt: String,
)
