package com.studiofreesia.wondaywall.services

import com.studiofreesia.wondaywall.models.GeneratedImageResult
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptGenerationResult

// 壁紙生成で使う AI サービスの共通インターフェース
interface AiService {
    suspend fun generatePrompt(
        context: PromptContext,
        serviceTier: GoogleAiServiceTier = GoogleAiServiceTier.Standard,
        onProgress: ((Double, String) -> Unit)? = null,
    ): PromptGenerationResult

    suspend fun fetchOgpImages(
        context: PromptContext,
        selectedNewsIds: List<String>,
    ): PromptContext

    suspend fun generateImageFromPrompt(
        imagePrompt: String,
        context: PromptContext,
        serviceTier: GoogleAiServiceTier = GoogleAiServiceTier.Standard,
        onProgress: ((Double, String) -> Unit)? = null,
    ): GeneratedImageResult
}
