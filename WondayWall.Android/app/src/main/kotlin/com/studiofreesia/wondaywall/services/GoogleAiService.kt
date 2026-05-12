package com.studiofreesia.wondaywall.services

import com.studiofreesia.wondaywall.models.GeneratedImageInfo
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptNewsTopic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

// Google AI Gemini API を使った壁紙画像生成サービス
class GoogleAiService(
    private val appConfigService: AppConfigService,
    private val filesDir: File,
) {
    companion object {
        private const val TEXT_MODEL_NAME = "gemini-3-flash-preview"
        private const val IMAGE_MODEL_NAME = "gemini-3.1-flash-image-preview"
        private const val API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"

        // 通常タイムアウト秒数
        private const val IMAGE_GENERATION_TIMEOUT_SEC = 300L
        // Flex モードのタイムアウト（キューに積まれるため長めに設定）
        private const val FLEX_TIMEOUT_SEC = 660L
    }

    private val jsonSerializer = Json {
        encodeDefaults = false
        ignoreUnknownKeys = true
    }

    // 壁紙画像を生成してローカルに保存し、GeneratedImageInfo を返す
    // serviceTier: バックグラウンド生成時は Flex を指定（失敗時は Standard にフォールバック）
    suspend fun generateWallpaper(
        context: PromptContext,
        serviceTier: GoogleAiServiceTier = GoogleAiServiceTier.Standard,
    ): GeneratedImageInfo {
        val apiKey = appConfigService.getConfig().googleAiApiKey
        if (apiKey.isEmpty()) {
            throw IllegalStateException("Google AI API キーが設定されていません。")
        }

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成（Flex→Standard フォールバック付き）
        val promptSelection = generatePromptSelectionWithFallback(context, apiKey, serviceTier)

        // ステップ2: 画像モデルで壁紙を生成（Flex→Standard フォールバック付き）
        val imageData = generateImageWithFallback(
            prompt = promptSelection.imagePrompt,
            context = context,
            selectedNewsIds = promptSelection.selectedNewsIds.toSet(),
            apiKey = apiKey,
            serviceTier = serviceTier,
        )

        // 画像をローカルに保存する
        val wallpapersDir = File(filesDir, "wallpapers").also { it.mkdirs() }
        val fileName = "wallpaper_${System.currentTimeMillis()}.${imageData.extension}"
        val file = File(wallpapersDir, fileName)
        file.writeBytes(imageData.bytes)

        return GeneratedImageInfo(
            filePath = file.absolutePath,
            imagePrompt = promptSelection.imagePrompt,
            selectedNewsIds = promptSelection.selectedNewsIds,
        )
    }

    // Flex → Standard フォールバック付きでプロンプトを生成する
    private suspend fun generatePromptSelectionWithFallback(
        context: PromptContext,
        apiKey: String,
        serviceTier: GoogleAiServiceTier,
    ): PromptSelectionResponse {
        if (serviceTier != GoogleAiServiceTier.Flex) {
            return generatePromptSelection(context, apiKey, GoogleAiServiceTier.Standard)
        }
        return try {
            generatePromptSelection(context, apiKey, GoogleAiServiceTier.Flex)
        } catch (e: IOException) {
            // Flex 容量不足（503/429）→ Standard で再試行
            if (isFlexUnavailableError(e)) {
                generatePromptSelection(context, apiKey, GoogleAiServiceTier.Standard)
            } else throw e
        }
    }

    // テキストモデルで画像プロンプト候補を生成する
    private suspend fun generatePromptSelection(
        context: PromptContext,
        apiKey: String,
        serviceTier: GoogleAiServiceTier,
    ): PromptSelectionResponse {
        val endpoint = "$API_BASE_URL/$TEXT_MODEL_NAME:generateContent?key=$apiKey"
        val systemPrompt = buildTextModelPrompt(context)

        val requestBody = GeminiRequest(
            contents = listOf(
                GeminiContent(
                    role = "user",
                    parts = listOf(GeminiPart(text = systemPrompt)),
                )
            ),
            generationConfig = GeminiGenerationConfig(
                responseMimeType = "application/json",
                responseSchema = promptSelectionSchema,
            ),
            tools = listOf(GeminiTool(googleSearch = GeminiGoogleSearch())),
            serviceTier = if (serviceTier == GoogleAiServiceTier.Flex) "flex" else null,
        )

        val responseText = postJson(
            url = endpoint,
            body = jsonSerializer.encodeToString(requestBody),
            timeoutSec = if (serviceTier == GoogleAiServiceTier.Flex) FLEX_TIMEOUT_SEC else IMAGE_GENERATION_TIMEOUT_SEC,
        )

        val response = jsonSerializer.decodeFromString<GeminiResponse>(responseText)
        val jsonText = response.candidates.firstOrNull()?.content?.parts?.firstOrNull()?.text
            ?: throw IOException("Google AI から有効なプロンプト選択レスポンスを取得できませんでした。")

        val selection = jsonSerializer.decodeFromString<PromptSelectionResponse>(jsonText)
        if (selection.imagePrompt.isEmpty()) {
            throw IOException("Google AI が有効な画像プロンプトを返しませんでした。")
        }
        return selection
    }

    // Flex → Standard フォールバック付きで画像を生成する
    private suspend fun generateImageWithFallback(
        prompt: String,
        context: PromptContext,
        selectedNewsIds: Set<String>,
        apiKey: String,
        serviceTier: GoogleAiServiceTier,
    ): ImageData {
        if (serviceTier != GoogleAiServiceTier.Flex) {
            return generateImage(prompt, context, selectedNewsIds, apiKey, GoogleAiServiceTier.Standard)
        }
        return try {
            generateImage(prompt, context, selectedNewsIds, apiKey, GoogleAiServiceTier.Flex)
        } catch (e: IOException) {
            if (isFlexUnavailableError(e)) {
                generateImage(prompt, context, selectedNewsIds, apiKey, GoogleAiServiceTier.Standard)
            } else throw e
        }
    }

    // 画像モデルで壁紙画像を生成する
    private suspend fun generateImage(
        prompt: String,
        context: PromptContext,
        selectedNewsIds: Set<String>,
        apiKey: String,
        serviceTier: GoogleAiServiceTier,
    ): ImageData = withContext(Dispatchers.IO) {
        val endpoint = "$API_BASE_URL/$IMAGE_MODEL_NAME:generateContent?key=$apiKey"

        // 選択済みニュースの OGP 画像 URL を収集する（最大3件）
        val ogpUrls = context.newsTopics
            .filter { selectedNewsIds.contains(it.id) }
            .mapNotNull { it.ogpImageUrl }
            .take(3)

        val imagePromptText = if (ogpUrls.isEmpty()) prompt else """
            $prompt

            Reference images from the selected news topics are attached. Incorporate their visual themes, color palette, and subject matter into the wallpaper design.
        """.trimIndent()

        val parts = mutableListOf<GeminiPart>()

        // ベース壁紙が指定されている場合は先頭に付加する
        if (context.baseImagePath != null) {
            val baseFile = File(context.baseImagePath)
            if (baseFile.exists()) {
                val mimeType = mimeTypeForPath(context.baseImagePath)
                val base64 = android.util.Base64.encodeToString(baseFile.readBytes(), android.util.Base64.NO_WRAP)
                parts += GeminiPart(inlineData = GeminiInlineData(mimeType = mimeType, data = base64))
                val finalPrompt = """
                    The current wallpaper is provided as the base image.
                    Create a new wallpaper that evolves gradually from this base.
                    Visually inspect the base wallpaper and compare it against the current prompt.
                    Treat the current prompt's events, news themes, and mood as the source of truth.
                    Remove or replace any subject, motif, decoration, or symbolic element from the base image that no longer matches the current prompt.
                    When the base image conflicts with the current prompt, prioritize the current prompt while preserving the base image's overall composition, color palette, and artistic style.
                    Preserve the overall composition, color palette, and artistic style of the base wallpaper. Incorporate the new themes and events subtly — avoid drastic visual changes.

                    $imagePromptText
                """.trimIndent()
                parts += GeminiPart(text = finalPrompt)
            } else {
                parts += GeminiPart(text = imagePromptText)
            }
        } else {
            parts += GeminiPart(text = imagePromptText)
        }

        // 選択済みニュースの OGP 画像をダウンロードしてインラインデータとして添付する
        val ogpClient = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()
        for (ogpUrl in ogpUrls) {
            try {
                val imgRequest = Request.Builder()
                    .url(ogpUrl)
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
                    .build()
                ogpClient.newCall(imgRequest).execute().use { response ->
                    if (response.isSuccessful) {
                        val bytes = response.body?.bytes() ?: return@use
                        val contentType = response.header("Content-Type") ?: "image/jpeg"
                        val mimeType = contentType.substringBefore(";").trim()
                        val base64 = android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
                        parts += GeminiPart(inlineData = GeminiInlineData(mimeType = mimeType, data = base64))
                    }
                }
            } catch (e: Exception) {
                // OGP 画像のダウンロード失敗は無視する
            }
        }

        val requestBody = GeminiRequest(
            contents = listOf(GeminiContent(role = "user", parts = parts)),
            generationConfig = GeminiGenerationConfig(
                responseModalities = listOf("IMAGE"),
                imageConfig = GeminiImageConfig(
                    aspectRatio = context.aspectRatio,
                    imageSize = context.imageSize,
                ),
            ),
            tools = listOf(GeminiTool(googleSearch = GeminiGoogleSearch())),
            serviceTier = if (serviceTier == GoogleAiServiceTier.Flex) "flex" else null,
        )

        val responseText = postJson(
            url = endpoint,
            body = jsonSerializer.encodeToString(requestBody),
            timeoutSec = if (serviceTier == GoogleAiServiceTier.Flex) FLEX_TIMEOUT_SEC else IMAGE_GENERATION_TIMEOUT_SEC,
        )

        val response = jsonSerializer.decodeFromString<GeminiResponse>(responseText)
        for (candidate in response.candidates) {
            for (part in candidate.content.parts) {
                val inlineData = part.inlineData ?: continue
                if (!inlineData.mimeType.startsWith("image/")) continue
                val bytes = android.util.Base64.decode(inlineData.data, android.util.Base64.DEFAULT)
                val ext = inlineData.mimeType.removePrefix("image/").let {
                    if (it.isEmpty()) "jpg" else it
                }
                return@withContext ImageData(bytes = bytes, extension = ext)
            }
        }
        throw IOException("Google AI から画像データを取得できませんでした。")
    }

    // テキストモデルに送るプロンプトを構築する
    private fun buildTextModelPrompt(context: PromptContext): String {
        val parts = mutableListOf<String>()

        parts += """
            You are an expert mobile wallpaper image-generation prompt writer.
            You will be given calendar events, news topics, and optionally reference images from those news articles.
            You MUST aggressively use Google Search before writing the prompt.
            Research broadly and actively: run multiple targeted searches per topic (official sources, recent coverage,
            image references, and related background context), then cross-check recency and consistency.
            Prefer fresh, high-signal information and concrete visual details you can translate into imagery.
            Do not rely only on the user's short summaries when searchable context exists.
            Your task: review all candidate calendar events and news topics, decide which ones should materially influence
            the wallpaper, and then write a single detailed, creative English prompt for an image generation model
            (${context.imageSize} resolution, ${context.aspectRatio} aspect ratio) that creates a beautiful Android wallpaper.

            The wallpaper should visually reflect the themes, mood, and atmosphere of the selected events and news.
            If reference images are supplied later, they will correspond only to selected news topics.
            Describe visual elements, style, mood, color palette, lighting, and composition in detail.
            No text, logos, or UI overlays. Portrait orientation.
            Place the most important visual elements in the center to avoid being hidden by status bar or navigation bar.

            For calendar events:
            - Only include POSITIVE events (celebrations, trips, parties, hobbies, achievements, social gatherings, etc.)
              in the visual design. Ignore NEGATIVE or NEUTRAL events (medical appointments, work deadlines,
              chores, administrative tasks, etc.), but do not let them suppress other event or news candidates.
            - Each event has a proximity tag indicating when it occurs. Use it to determine the visual weight:
              [today] or [tomorrow]: this event DOMINATES the entire image — make it the primary subject and theme,
                occupying nearly all visual elements.
              [in 2-3 days]: this event is a MAJOR visual theme, occupying 50–70% of the image's visual elements.
              [in 4-7 days]: this event is a MINOR accent or background element (15–30% of visual elements).
            - When multiple positive events are present, prioritize the ones happening sooner.
            - If the nearest event is NEGATIVE or NEUTRAL, ignore it and continue considering later positive events
              and news topics as potential primary themes.

            Return a response that matches the configured JSON schema.
            - imagePrompt must be a single detailed English prompt for the image model.
            - selectedNewsIds must contain only ids of news topics that materially influenced imagePrompt.
            - If no news topic is used, selectedNewsIds must be an empty array.
            - Do not output markdown fences or any extra explanation.
        """.trimIndent()

        if (context.baseImagePath != null && File(context.baseImagePath).exists()) {
            parts += """
                A base wallpaper image will be supplied to the image model.
                Preserve the overall composition, color palette, and artistic style of the base wallpaper.
                Incorporate the new themes and events subtly — avoid drastic visual changes.
            """.trimIndent()
        }

        if (context.calendarEvents.isNotEmpty()) {
            val eventsJson = jsonSerializer.encodeToString(context.calendarEvents)
            parts += "Calendar event candidates (JSON):\n$eventsJson"
        }

        if (context.newsTopics.isNotEmpty()) {
            // OGP 画像 URL は後から添付するため、ここでは除外して送らない
            val topicsForPrompt = context.newsTopics.map {
                PromptNewsTopic(
                    id = it.id, title = it.title, summary = it.summary,
                    url = it.url, publishedAt = it.publishedAt, ogpImageUrl = null,
                )
            }
            val newsJson = jsonSerializer.encodeToString(topicsForPrompt)
            parts += "News topic candidates (JSON):\n$newsJson"
        }

        if (context.additionalConstraints.isNotEmpty()) {
            parts += "Additional instructions: ${context.additionalConstraints}"
        }

        return parts.joinToString("\n\n")
    }

    // JSON を POST してレスポンス文字列を返す
    private fun postJson(url: String, body: String, timeoutSec: Long): String {
        val client = OkHttpClient.Builder()
            .callTimeout(timeoutSec, TimeUnit.SECONDS)
            .build()
        val requestBody = body.toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .post(requestBody)
            .build()
        client.newCall(request).execute().use { response ->
            val responseBody = response.body?.string() ?: ""
            if (!response.isSuccessful) {
                throw IOException("Google AI API エラー (${response.code}): $responseBody")
            }
            return responseBody
        }
    }

    // Flex 容量不足を示すエラーか判定する（503 / 429）
    private fun isFlexUnavailableError(e: IOException): Boolean {
        val msg = e.message ?: return false
        return msg.contains("503") || msg.contains("429")
    }

    // ファイルパスから MIME タイプを判定する
    private fun mimeTypeForPath(path: String): String =
        when (path.substringAfterLast('.').lowercase()) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "webp" -> "image/webp"
            else -> "image/jpeg"
        }

    // PromptSelectionSchema（テキストモデルへのレスポンススキーマ）
    private val promptSelectionSchema: JsonObject = buildJsonObject {
        put("type", "object")
        putJsonObject("properties") {
            putJsonObject("imagePrompt") { put("type", "string") }
            putJsonObject("selectedNewsIds") {
                put("type", "array")
                putJsonObject("items") { put("type", "string") }
            }
        }
        putJsonArray("required") {
            add(kotlinx.serialization.json.JsonPrimitive("imagePrompt"))
            add(kotlinx.serialization.json.JsonPrimitive("selectedNewsIds"))
        }
    }

    // 画像データの一時保持用
    private data class ImageData(val bytes: ByteArray, val extension: String)

    // ──────────────────────────────────────────────
    // Gemini API リクエスト/レスポンスモデル
    // ──────────────────────────────────────────────

    @Serializable
    private data class GeminiRequest(
        val contents: List<GeminiContent>,
        val generationConfig: GeminiGenerationConfig? = null,
        val tools: List<GeminiTool>? = null,
        // Flex 推論時は "flex"、通常は null（省略すると Standard）
        @SerialName("service_tier") val serviceTier: String? = null,
    )

    @Serializable
    private data class GeminiContent(
        val role: String,
        val parts: List<GeminiPart>,
    )

    @Serializable
    private data class GeminiPart(
        val text: String? = null,
        val inlineData: GeminiInlineData? = null,
    )

    @Serializable
    private data class GeminiInlineData(
        val mimeType: String,
        val data: String,
    )

    @Serializable
    private data class GeminiGenerationConfig(
        val responseMimeType: String? = null,
        val responseSchema: JsonObject? = null,
        val responseModalities: List<String>? = null,
        val imageConfig: GeminiImageConfig? = null,
    )

    @Serializable
    private data class GeminiImageConfig(
        val aspectRatio: String,
        val imageSize: String,
    )

    @Serializable
    private data class GeminiTool(
        val googleSearch: GeminiGoogleSearch? = null,
    )

    @Serializable
    private class GeminiGoogleSearch

    @Serializable
    private data class GeminiResponse(
        val candidates: List<GeminiCandidate>,
    )

    @Serializable
    private data class GeminiCandidate(
        val content: GeminiResponseContent,
    )

    @Serializable
    private data class GeminiResponseContent(
        val parts: List<GeminiResponsePart>,
    )

    @Serializable
    private data class GeminiResponsePart(
        val text: String? = null,
        val inlineData: GeminiResponseInlineData? = null,
    )

    @Serializable
    private data class GeminiResponseInlineData(
        val mimeType: String,
        val data: String,
    )

    @Serializable
    private data class PromptSelectionResponse(
        val imagePrompt: String,
        val selectedNewsIds: List<String>,
    )
}
