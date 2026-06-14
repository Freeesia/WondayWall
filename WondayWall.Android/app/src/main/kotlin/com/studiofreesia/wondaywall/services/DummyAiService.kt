package com.studiofreesia.wondaywall.services

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import com.studiofreesia.wondaywall.models.DebugConfig
import com.studiofreesia.wondaywall.models.GeneratedImageResult
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptGenerationResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.time.Clock
import kotlin.time.Duration.Companion.hours
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.random.Random

// 実 API を使わずに遅延付きで動作を再現するダミー実装（Debug ビルド専用）
class DummyAiService(
    private val appConfigService: AppConfigService,
    private val cacheDir: File,
) : AiService {

    override suspend fun generatePrompt(
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Unit)?,
    ): PromptGenerationResult {
        val delaySeconds = appConfigService.getDebugConfig().dummyPromptDelaySeconds
        val news = buildDummyNews(appConfigService.getDebugConfig().dummyNewsCount)
        simulateProgress(
            totalSeconds = delaySeconds,
            message = "[Dummy] 画像生成プロンプトの生成中",
            onProgress = onProgress,
        )
        return PromptGenerationResult(
            imagePrompt = "[Dummy] Simulated Android wallpaper prompt",
            selectedNewsTopics = news,
        )
    }

    override suspend fun fetchOgpImages(
        context: PromptContext,
        selectedNewsTopics: List<NewsTopicItem>,
    ): PromptContext = context

    override suspend fun generateImageFromPrompt(
        imagePrompt: String,
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Unit)?,
    ): GeneratedImageResult {
        val delaySeconds = appConfigService.getDebugConfig().dummyImageDelaySeconds
        simulateProgress(
            totalSeconds = delaySeconds,
            message = "[Dummy] 壁紙画像の生成中",
            onProgress = onProgress,
        )
        return GeneratedImageResult(
            temporaryFilePath = saveDummyImage(context),
            imagePrompt = imagePrompt,
        )
    }

    // 指定時間かけて擬似進捗を通知する
    private suspend fun simulateProgress(
        totalSeconds: Int,
        message: String,
        onProgress: ((Double, String) -> Unit)?,
    ) {
        val duration = max(totalSeconds, 1)
        onProgress?.invoke(0.0, message)
        repeat(duration) { index ->
            delay(1_000)
            onProgress?.invoke((index + 1).toDouble() / duration.toDouble(), message)
        }
    }

    private suspend fun saveDummyImage(context: PromptContext): String = withContext(Dispatchers.IO) {
        val (width, height) = dummyCanvasSize(context)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val seed = System.currentTimeMillis()
        val random = Random(seed)
        val colors = IntArray(3) {
            Color.HSVToColor(
                floatArrayOf(
                    (random.nextInt(360)).toFloat(),
                    random.nextDouble(0.45, 0.85).toFloat(),
                    random.nextDouble(0.45, 0.95).toFloat(),
                )
            )
        }

        paint.shader = LinearGradient(
            0f,
            0f,
            width.toFloat(),
            height.toFloat(),
            colors,
            null,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), paint)

        paint.shader = null
        repeat(10) {
            paint.color = Color.argb(
                random.nextInt(48, 132),
                random.nextInt(255),
                random.nextInt(255),
                random.nextInt(255),
            )
            canvas.drawCircle(
                random.nextInt(width).toFloat(),
                random.nextInt(height).toFloat(),
                random.nextInt(width / 10, width / 3).toFloat(),
                paint,
            )
        }

        val wallpapersDir = File(cacheDir, "wallpaper-staging").also { it.mkdirs() }
        val file = File(wallpapersDir, "wallpaper_${System.currentTimeMillis()}.png")
        file.outputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
        }
        bitmap.recycle()
        file.absolutePath
    }

    // PromptContext の imageSize / aspectRatio からキャンバスサイズを決める
    private fun dummyCanvasSize(context: PromptContext): Pair<Int, Int> {
        val longEdge = when (context.imageSize.uppercase()) {
            "4K" -> 2048
            "2K" -> 1440
            "1K" -> 1024
            "512" -> 512
            else -> 1024
        }
        val ratio = parseAspectRatio(context.aspectRatio)
        return if (ratio <= 1.0) {
            (longEdge * ratio).roundToInt().coerceAtLeast(256) to longEdge
        } else {
            longEdge to (longEdge / ratio).roundToInt().coerceAtLeast(256)
        }
    }

    private fun parseAspectRatio(value: String): Double {
        val parts = value.split(":")
        if (parts.size != 2) return 9.0 / 16.0
        val width = parts[0].toDoubleOrNull() ?: return 9.0 / 16.0
        val height = parts[1].toDoubleOrNull() ?: return 9.0 / 16.0
        if (width <= 0.0 || height <= 0.0) return 9.0 / 16.0
        return width / height
    }

    // RSSへアクセスせず、件数指定だけで安定した表示確認を行う。
    private fun buildDummyNews(count: Int): List<NewsTopicItem> {
        val normalizedCount = count.coerceIn(DebugConfig.MIN_NEWS_COUNT, DebugConfig.MAX_NEWS_COUNT)
        if (normalizedCount == 0) return emptyList()

        val now = Clock.System.now()
        val templates = listOf(
            DummyNewsTemplate(
                title = "ダミーニュース{n}: 週末の空模様と街イベントの見どころ",
                summary = "週末に楽しめる屋外イベントと天気の変化をまとめたダミーニュースです。",
            ),
            DummyNewsTemplate(
                title = "ダミーニュース{n}: 新しい生成AIツールが公開、制作ワークフローを短縮",
                summary = "デザインや文章作成を支援する新機能の概要を紹介するダミーニュースです。",
            ),
            DummyNewsTemplate(
                title = "ダミーニュース{n}: 夜景スポットでライトアップ企画が開始",
                summary = "季節限定のライトアップと周辺のおすすめルートを扱うダミーニュースです。",
            ),
            DummyNewsTemplate(
                title = "ダミーニュース{n}: 宇宙観測プロジェクトが新しい画像を公開",
                summary = "星雲や銀河の観測成果をビジュアル中心に伝えるダミーニュースです。",
            ),
            DummyNewsTemplate(
                title = "ダミーニュース{n}: 地域マーケットに限定スイーツが登場",
                summary = "週末の買い物や散歩の参考になる食の話題を想定したダミーニュースです。",
            ),
        )

        return (0 until normalizedCount).map { index ->
            val number = index + 1
            val template = templates[index % templates.size]
            NewsTopicItem(
                id = "dummy-news-$number",
                title = template.title.replace("{n}", number.toString()),
                summary = template.summary,
                url = "https://example.com/wondaywall/dummy-news-$number",
                publishedAt = now - (index + 1).hours,
                ogpImageUrl = null,
            )
        }
    }

    private data class DummyNewsTemplate(
        val title: String,
        val summary: String,
    )
}
