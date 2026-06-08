package com.studiofreesia.wondaywall.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import com.studiofreesia.wondaywall.App
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.GenerationProgress
import com.studiofreesia.wondaywall.models.NewsTopicItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

// 既存サービスからウィジェット表示状態を組み立てるリポジトリ
class WidgetStateRepository(private val context: Context) {
    suspend fun load(): WidgetDisplayState {
        val app = context.applicationContext as App
        val config = app.appConfigService.getConfig()
        val isConfigured = config.googleAiApiKey.trim().isNotEmpty()
        val currentSlotStartedAtMillis = app.taskSchedulerService.getCurrentSlotStartedAtMillis()
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
        val usedEvents = slotHistory?.usedCalendarEvents?.takeIf { it.isNotEmpty() }
            ?: latestSuccess?.usedCalendarEvents?.takeIf { it.isNotEmpty() }
            ?: emptyList()
        val displayNews = usedNews.take(8)

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
            backgroundImage = imageHistory?.appliedImageUri?.let { loadWidgetBitmap(it) },
            canOpenGenerationConfirmation = isConfigured && !isGenerating && !isCurrentSlotProcessed,
            usedCalendarEvents = usedEvents.take(4),
            usedNewsTopics = displayNews,
            faviconImages = loadFaviconImages(displayNews),
        )
    }

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

    private suspend fun loadFaviconImages(news: List<NewsTopicItem>): Map<String, Bitmap> = withContext(Dispatchers.IO) {
        news.mapNotNull { item ->
            val bitmap = loadFaviconBitmap(item.url) ?: return@mapNotNull null
            item.id to bitmap
        }.toMap()
    }

    private fun loadFaviconBitmap(urlString: String?): Bitmap? {
        val host = normalizedHost(urlString) ?: return null
        val cacheFile = faviconCacheFile(host)
        if (cacheFile.exists() && cacheFile.length() > 0L) {
            BitmapFactory.decodeFile(cacheFile.path)?.let { return it }
        }

        val connection = runCatching {
            URL(faviconUrl(host)).openConnection() as HttpURLConnection
        }.getOrNull() ?: return null

        return runCatching {
            connection.connectTimeout = 4_000
            connection.readTimeout = 4_000
            connection.instanceFollowRedirects = true
            if (connection.responseCode !in 200 until 300) return@runCatching null
            val bytes = connection.inputStream.use { it.readBytes() }
            val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@runCatching null
            cacheFile.parentFile?.mkdirs()
            val tempFile = File(cacheFile.parentFile, "${cacheFile.name}.tmp")
            tempFile.writeBytes(bytes)
            if (!tempFile.renameTo(cacheFile)) {
                tempFile.copyTo(cacheFile, overwrite = true)
                tempFile.delete()
            }
            bitmap
        }.getOrNull().also {
            connection.disconnect()
        }
    }

    private fun normalizedHost(urlString: String?): String? {
        if (urlString.isNullOrBlank()) return null
        val uri = runCatching { Uri.parse(urlString) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase(Locale.US)
        if (scheme != "http" && scheme != "https") return null
        return uri.host?.lowercase(Locale.US)
    }

    private fun faviconUrl(host: String): String =
        Uri.Builder()
            .scheme("https")
            .authority("www.google.com")
            .path("s2/favicons")
            .appendQueryParameter("domain", host)
            .appendQueryParameter("sz", "64")
            .build()
            .toString()

    private fun faviconCacheFile(host: String): File {
        val safeName = buildString {
            host.forEach { char ->
                if (char.isLetterOrDigit()) append(char) else append('_')
            }
        }
        return File(File(context.cacheDir, "favicons"), "$safeName.png")
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
    val backgroundImage: Bitmap?,
    val canOpenGenerationConfirmation: Boolean,
    val usedCalendarEvents: List<CalendarEventItem>,
    val usedNewsTopics: List<NewsTopicItem>,
    val faviconImages: Map<String, Bitmap>,
)
