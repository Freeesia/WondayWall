package com.studiofreesia.wondaywall.services

import com.google.genai.Client
import com.google.genai.types.Blob
import com.google.genai.types.Content
import com.google.genai.types.GenerateContentConfig
import com.google.genai.types.GoogleSearch
import com.google.genai.types.Part
import com.google.genai.types.Schema
import com.google.genai.types.Tool
import com.studiofreesia.wondaywall.models.GeneratedImageInfo
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.PromptCalendarEvent
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptNewsTopic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit

// Google AI Gemini API を使った壁紙画像生成サービス（google-genai SDK 使用）
class GoogleAiService(
    private val appConfigService: AppConfigService,
    private val filesDir: File,
) {
    companion object {
        private const val TEXT_MODEL_NAME = "gemini-3-flash-preview"
        private const val IMAGE_MODEL_NAME = "gemini-3.1-flash-image-preview"
    }

    private val json = Json { ignoreUnknownKeys = true }

    // OGP 画像取得用 OkHttp クライアント（google-genai SDK に含まれないため独立して保持する）
    private val ogpHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

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

        val client = Client.builder().apiKey(apiKey).build()

        // ステップ1: テキストモデルで詳細な画像プロンプトを生成（Flex→Standard フォールバック付き）
        val promptSelection = generatePromptSelectionWithFallback(client, context, serviceTier)

        // ステップ2: 画像モデルで壁紙を生成（Flex→Standard フォールバック付き）
        val imageData = generateImageWithFallback(
            client = client,
            prompt = promptSelection.imagePrompt,
            context = context,
            selectedNewsIds = promptSelection.selectedNewsIds.toSet(),
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
        client: Client,
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
    ): PromptSelectionResponse {
        if (serviceTier != GoogleAiServiceTier.Flex) {
            return generatePromptSelection(client, context, GoogleAiServiceTier.Standard)
        }
        return try {
            generatePromptSelection(client, context, GoogleAiServiceTier.Flex)
        } catch (e: IOException) {
            // Flex 容量不足（503/429）→ Standard で再試行
            if (isFlexUnavailableError(e)) {
                generatePromptSelection(client, context, GoogleAiServiceTier.Standard)
            } else throw e
        }
    }

    // テキストモデルで画像プロンプト候補を生成する
    private suspend fun generatePromptSelection(
        client: Client,
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
    ): PromptSelectionResponse = withContext(Dispatchers.IO) {
        val systemPrompt = buildTextModelPrompt(context)

        // レスポンススキーマ（imagePrompt + selectedNewsIds の JSON オブジェクト）
        val schema = Schema.builder()
            .type("OBJECT")
            .properties(
                mapOf(
                    "imagePrompt" to Schema.builder().type("STRING").build(),
                    "selectedNewsIds" to Schema.builder()
                        .type("ARRAY")
                        .items(Schema.builder().type("STRING").build())
                        .build(),
                )
            )
            .required(listOf("imagePrompt", "selectedNewsIds"))
            .build()

        val configBuilder = GenerateContentConfig.builder()
            .responseMimeType("application/json")
            .responseSchema(schema)
            .tools(listOf(Tool.builder().googleSearch(GoogleSearch.builder().build()).build()))
        if (serviceTier == GoogleAiServiceTier.Flex) {
            // Flex ティアは SDK の serviceTier フィールドで設定する
            configBuilder.serviceTier("flex")
        }
        val config = configBuilder.build()

        val content = Content.builder()
            .role("user")
            .parts(listOf(Part.builder().text(systemPrompt).build()))
            .build()

        val response = client.models.generateContent(TEXT_MODEL_NAME, content, config)
        val jsonText = response.text()
            ?: throw IOException("Google AI から有効なプロンプト選択レスポンスを取得できませんでした。")

        val selection = json.decodeFromString<PromptSelectionResponse>(jsonText)
        if (selection.imagePrompt.isEmpty()) {
            throw IOException("Google AI が有効な画像プロンプトを返しませんでした。")
        }
        selection
    }

    // Flex → Standard フォールバック付きで画像を生成する
    private suspend fun generateImageWithFallback(
        client: Client,
        prompt: String,
        context: PromptContext,
        selectedNewsIds: Set<String>,
        serviceTier: GoogleAiServiceTier,
    ): ImageData {
        if (serviceTier != GoogleAiServiceTier.Flex) {
            return generateImage(client, prompt, context, selectedNewsIds, GoogleAiServiceTier.Standard)
        }
        return try {
            generateImage(client, prompt, context, selectedNewsIds, GoogleAiServiceTier.Flex)
        } catch (e: IOException) {
            if (isFlexUnavailableError(e)) {
                generateImage(client, prompt, context, selectedNewsIds, GoogleAiServiceTier.Standard)
            } else throw e
        }
    }

    // 画像モデルで壁紙画像を生成する
    private suspend fun generateImage(
        client: Client,
        prompt: String,
        context: PromptContext,
        selectedNewsIds: Set<String>,
        serviceTier: GoogleAiServiceTier,
    ): ImageData = withContext(Dispatchers.IO) {
        // 選択済みニュースの OGP 画像 URL を収集する（最大3件）
        val ogpUrls = context.newsTopics
            .filter { selectedNewsIds.contains(it.id) }
            .mapNotNull { it.ogpImageUrl }
            .take(3)

        val imagePromptText = if (ogpUrls.isEmpty()) prompt else """
            $prompt

            Reference images from the selected news topics are attached. Incorporate their visual themes, color palette, and subject matter into the wallpaper design.
        """.trimIndent()

        val parts = mutableListOf<Part>()
        parts += Part.builder().text(imagePromptText).build()

        // 選択済みニュースの OGP 画像をダウンロードしてインラインデータとして添付する
        for (ogpUrl in ogpUrls) {
            try {
                val imgRequest = Request.Builder()
                    .url(ogpUrl)
                    .header("User-Agent", "Mozilla/5.0 (Linux; Android 14)")
                    .build()
                ogpHttpClient.newCall(imgRequest).execute().use { response ->
                    if (response.isSuccessful) {
                        val bytes = response.body?.bytes() ?: return@use
                        val mimeType = (response.header("Content-Type") ?: "image/jpeg")
                            .substringBefore(";").trim()
                        val blob = Blob.builder().mimeType(mimeType).data(bytes).build()
                        parts += Part.builder().inlineData(blob).build()
                    }
                }
            } catch (_: Exception) {
                // OGP 画像のダウンロード失敗は無視する
            }
        }

        val configBuilder = GenerateContentConfig.builder()
            .responseModalities(listOf("IMAGE"))
        if (serviceTier == GoogleAiServiceTier.Flex) {
            configBuilder.serviceTier("flex")
        }
        val config = configBuilder.build()

        val content = Content.builder()
            .role("user")
            .parts(parts)
            .build()

        val response = client.models.generateContent(IMAGE_MODEL_NAME, content, config)

        for (candidate in response.candidates() ?: emptyList()) {
            for (part in candidate.content()?.parts() ?: emptyList()) {
                val blob = part.inlineData() ?: continue
                if (blob.mimeType()?.startsWith("image/") != true) continue
                val bytes = blob.data() ?: continue
                val ext = blob.mimeType()!!.removePrefix("image/").let {
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

        if (context.calendarEvents.isNotEmpty()) {
            val eventsJson = json.encodeToString(
                ListSerializer(PromptCalendarEvent.serializer()),
                context.calendarEvents
            )
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
            val newsJson = json.encodeToString(
                ListSerializer(PromptNewsTopic.serializer()),
                topicsForPrompt
            )
            parts += "News topic candidates (JSON):\n$newsJson"
        }

        if (context.additionalConstraints.isNotEmpty()) {
            parts += "Additional instructions: ${context.additionalConstraints}"
        }

        return parts.joinToString("\n\n")
    }

    // Flex 容量不足を示すエラーか判定する（503 / 429）
    private fun isFlexUnavailableError(e: IOException): Boolean {
        val msg = e.message ?: return false
        return msg.contains("503") || msg.contains("429")
    }

    // 画像データの一時保持用
    private data class ImageData(val bytes: ByteArray, val extension: String)

    // テキストモデルのレスポンス（JSON スキーマに合わせた構造体）
    @Serializable
    private data class PromptSelectionResponse(
        val imagePrompt: String,
        val selectedNewsIds: List<String>,
    )
}
