package com.studiofreesia.wondaywall.services

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import com.studiofreesia.wondaywall.models.GeneratedImageResult
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptGenerationResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.random.Random

// 実 API を使わずに遅延付きで動作を再現するダミー実装（Debug ビルド専用）
class DummyAiService(
    private val appConfigService: AppConfigService,
    private val filesDir: File,
) : AiService {

    override suspend fun generatePrompt(
        context: PromptContext,
        serviceTier: GoogleAiServiceTier,
        onProgress: ((Double, String) -> Unit)?,
    ): PromptGenerationResult {
        val delaySeconds = appConfigService.getDebugConfig().dummyPromptDelaySeconds
        simulateProgress(
            totalSeconds = delaySeconds,
            message = "[Dummy] 画像生成プロンプトの生成中",
            onProgress = onProgress,
        )
        return PromptGenerationResult(
            imagePrompt = "[Dummy] Simulated Android wallpaper prompt",
            selectedNewsIds = emptyList(),
        )
    }

    override suspend fun fetchOgpImages(
        context: PromptContext,
        selectedNewsIds: List<String>,
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
            filePath = saveDummyImage(context),
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

        val wallpapersDir = File(filesDir, "wallpapers").also { it.mkdirs() }
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
}
