package com.studiofreesia.wondaywall.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.studiofreesia.wondaywall.App
import com.studiofreesia.wondaywall.models.GenerationProgress
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

// 既存サービスからウィジェット表示状態を組み立てるリポジトリ
class WidgetStateRepository(private val context: Context) {
    suspend fun load(): WidgetDisplayState {
        val app = context.applicationContext as App
        val config = app.appConfigService.getConfig()
        val isConfigured = config.googleAiApiKey.trim().isNotEmpty()
        val currentSlotStartedAtMillis = app.taskSchedulerService.getCurrentSlotStartedAtMillis()
        val nextSlotStartsAtMillis = app.taskSchedulerService.getNextSlotStartedAtMillis()
        val history = app.historyService.loadHistory()
        val lastCompleted = history.firstOrNull { !it.isGenerating }
        val isCurrentSlotProcessed =
            lastCompleted?.executedAt?.toEpochMilliseconds()?.let { it >= currentSlotStartedAtMillis } == true
        val progress = app.generationCoordinator.progress.value
            ?: app.taskSchedulerService.getCurrentProgress()
        val isGenerating = app.generationCoordinator.isGenerating.value ||
            app.taskSchedulerService.isGenerationWorkRunning()

        val slotHistory = history.firstOrNull {
            !it.isGenerating && it.executedAt.toEpochMilliseconds() >= currentSlotStartedAtMillis
        }
        val latestSuccess = history.firstOrNull { it.isSuccess && !it.isSkipped }
        val imageHistory = if (!slotHistory?.appliedImageUri.isNullOrBlank()) {
            slotHistory
        } else {
            latestSuccess
        }
        val usedNews = slotHistory?.usedNewsTopics?.takeIf { it.isNotEmpty() }
            ?: latestSuccess?.usedNewsTopics?.takeIf { it.isNotEmpty() }
            ?: emptyList()

        val status = when {
            !isConfigured -> WidgetSlotStatus.Unconfigured
            isGenerating -> WidgetSlotStatus.Generating
            isCurrentSlotProcessed -> WidgetSlotStatus.Processed
            else -> WidgetSlotStatus.Pending
        }

        return WidgetDisplayState(
            status = status,
            isGenerating = isGenerating,
            generationProgress = progress,
            isCurrentSlotProcessed = isCurrentSlotProcessed,
            currentSlotStartedAtMillis = currentSlotStartedAtMillis,
            nextSlotStartsAtMillis = nextSlotStartsAtMillis,
            latestDisplayHistory = imageHistory?.toWidgetHistory(),
            canOpenGenerationConfirmation = isConfigured && !isGenerating && !isCurrentSlotProcessed,
            usedNewsTopics = usedNews.take(3),
        )
    }

    private suspend fun HistoryItem.toWidgetHistory(): WidgetDisplayHistory =
        WidgetDisplayHistory(
            id = id,
            executedAtMillis = executedAt.toEpochMilliseconds(),
            status = status.name,
            image = appliedImageUri?.let { loadWidgetBitmap(it) },
        )

    private suspend fun loadWidgetBitmap(reference: String): Bitmap? = withContext(Dispatchers.IO) {
        runCatching {
            fun openStream() = Uri.parse(reference).let { uri ->
                when (uri.scheme) {
                    null, "" -> File(reference).takeIf { it.exists() }?.inputStream()
                    "file" -> uri.path?.let { File(it) }?.takeIf { it.exists() }?.inputStream()
                    "content" -> context.contentResolver.openInputStream(uri)
                    else -> null
                }
            }

            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            val boundsStream = openStream() ?: return@runCatching null
            boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return@runCatching null

            val sampleSize = calculateSampleSize(bounds.outWidth, bounds.outHeight)
            val options = BitmapFactory.Options().apply { inSampleSize = sampleSize }
            openStream()?.use { BitmapFactory.decodeStream(it, null, options) }
        }.getOrNull()
    }

    private fun calculateSampleSize(width: Int, height: Int): Int {
        var sampleSize = 1
        val maxSide = maxOf(width, height)
        while (maxSide / sampleSize > 640) {
            sampleSize *= 2
        }
        return sampleSize.coerceAtLeast(1)
    }
}

enum class WidgetSlotStatus {
    Unconfigured,
    Pending,
    Processed,
    Generating,
}

data class WidgetDisplayState(
    val status: WidgetSlotStatus,
    val isGenerating: Boolean,
    val generationProgress: GenerationProgress?,
    val isCurrentSlotProcessed: Boolean,
    val currentSlotStartedAtMillis: Long,
    val nextSlotStartsAtMillis: Long,
    val latestDisplayHistory: WidgetDisplayHistory?,
    val canOpenGenerationConfirmation: Boolean,
    val usedNewsTopics: List<NewsTopicItem>,
)

data class WidgetDisplayHistory(
    val id: String,
    val executedAtMillis: Long,
    val status: String,
    val image: Bitmap?,
)
