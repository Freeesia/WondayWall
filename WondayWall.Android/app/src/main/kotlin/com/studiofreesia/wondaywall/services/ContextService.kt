package com.studiofreesia.wondaywall.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import com.prof18.rssparser.RssParserBuilder
import com.prof18.rssparser.model.RssItem
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.CalendarSourceItem
import com.studiofreesia.wondaywall.models.ContextBuildResult
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.models.PromptCalendarEvent
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptNewsTopic
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.io.File
import java.net.URI
import java.security.MessageDigest
import kotlin.time.Clock
import kotlin.time.Instant
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jsoup.Jsoup
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours

// 画像生成に使うコンテキストを構築するサービス
class ContextService(
    private val context: Context,
    private val appConfigService: AppConfigService,
) {
    // RSS 取得・OGP ページ取得に使う OkHttp クライアント
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    private val rssParser = RssParserBuilder(callFactory = httpClient).build()
    private val cacheJson = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    // 入力URLからRSS URLを解決する（RSS URLが直接入力された場合はそのまま返す）
    suspend fun resolveRssSourceUrl(sourceUrl: String): String? {
        val sourceUri = try {
            URI(sourceUrl)
        } catch (_: Exception) {
            return null
        }

        val scheme = sourceUri.scheme?.lowercase() ?: return null
        if (scheme != "http" && scheme != "https") return null

        if (isLikelyRssUrl(sourceUri)) return sourceUrl

        return withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder()
                    .url(sourceUrl)
                    .header("User-Agent", "WondayWall/1.0")
                    .build()
                val html = httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@withContext null
                    response.body?.string() ?: return@withContext null
                }
                val doc = Jsoup.parse(html, sourceUrl)
                doc.select("link[rel][type][href]").firstNotNullOfOrNull { link ->
                    val rel = link.attr("rel")
                    if (!containsToken(rel, "alternate")) return@firstNotNullOfOrNull null

                    val type = link.attr("type")
                    if (!isFeedContentType(type)) return@firstNotNullOfOrNull null

                    val absoluteHref = link.absUrl("href")
                    if (absoluteHref.isNotBlank()) {
                        return@firstNotNullOfOrNull absoluteHref
                    }

                    val href = link.attr("href")
                    if (href.isBlank()) return@firstNotNullOfOrNull null
                    try {
                        sourceUri.resolve(href).toString()
                    } catch (_: Exception) {
                        null
                    }
                }
            } catch (_: Exception) {
                null
            }
        }
    }

    // PromptContext を構築して返す
    // onProgress はプロンプト生成開始前までの全体進捗 0.0〜1.0 の値を通知する
    suspend fun buildPromptContext(onProgress: ((Double, String) -> Unit)? = null): ContextBuildResult {
        val config = appConfigService.getConfig()

        // カレンダーイベントを取得する
        onProgress?.invoke(0.05, "カレンダーの取得中")
        val calendarEvents = getCalendarEvents(config.targetCalendarIds)
        onProgress?.invoke(0.08, "カレンダーの取得完了")

        // ニュースを取得する（最大10件）
        val newsTopics = runWithSyntheticProgress(
            start = 0.10,
            maxBeforeCompletion = 0.14,
            message = "ニュースの取得中",
            onProgress = onProgress,
        ) {
            fetchAllNews(config.rssSources).take(10)
        }
        onProgress?.invoke(0.14, "ニュース画像情報の取得完了")

        val promptContext = PromptContext(
            calendarEvents = calendarEvents.map { it.toPromptCalendarEvent() },
            newsTopics = newsTopics.map { it.toPromptNewsTopic() },
            additionalConstraints = config.userPrompt,
        )
        onProgress?.invoke(0.15, "コンテキスト生成完了")

        return ContextBuildResult(
            promptContext = promptContext,
            calendarEvents = calendarEvents,
            newsTopics = newsTopics,
        )
    }

    // RSS/OGP 取得のように実進捗が取れない処理を、指定範囲内の合成進捗として通知する
    private suspend fun <T> runWithSyntheticProgress(
        start: Double,
        maxBeforeCompletion: Double,
        message: String,
        onProgress: ((Double, String) -> Unit)?,
        block: suspend () -> T,
    ): T {
        if (onProgress == null) return block()
        return coroutineScope {
            var emitted = start.coerceIn(0.0, maxBeforeCompletion)
            onProgress(emitted, message)
            val progressJob = launch {
                while (isActive && emitted < maxBeforeCompletion) {
                    delay(1_000)
                    emitted = (emitted + 0.02).coerceAtMost(maxBeforeCompletion)
                    onProgress(emitted, message)
                }
            }
            try {
                block()
            } finally {
                progressJob.cancelAndJoin()
            }
        }
    }

    // READ_CALENDAR 権限があるか確認する
    fun hasCalendarPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context, Manifest.permission.READ_CALENDAR
        ) == PackageManager.PERMISSION_GRANTED

    // 端末に同期済みのカレンダー一覧を取得する
    fun getCalendarSources(): List<CalendarSourceItem> {
        if (!hasCalendarPermission()) return emptyList()

        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME,
            CalendarContract.Calendars.ACCOUNT_NAME,
            CalendarContract.Calendars.CALENDAR_COLOR,
        )

        val result = mutableListOf<CalendarSourceItem>()
        context.contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection, null, null, CalendarContract.Calendars.CALENDAR_DISPLAY_NAME
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars._ID)
            val nameIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME)
            val accountIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.ACCOUNT_NAME)
            val colorIdx = cursor.getColumnIndexOrThrow(CalendarContract.Calendars.CALENDAR_COLOR)
            while (cursor.moveToNext()) {
                result += CalendarSourceItem(
                    id = cursor.getLong(idIdx).toString(),
                    displayName = cursor.getString(nameIdx) ?: "",
                    accountName = cursor.getString(accountIdx) ?: "",
                    color = cursor.getInt(colorIdx),
                )
            }
        }
        return result
    }

    // カレンダーイベントを取得する（今日から7日以内）
    fun getCalendarEvents(targetCalendarIds: List<String>): List<CalendarEventItem> {
        if (!hasCalendarPermission()) return emptyList()

        val now = Clock.System.now()
        val rangeStart = now.toEpochMilliseconds()
        val rangeEnd = (now + 7.days).toEpochMilliseconds()

        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.CALENDAR_ID,
            CalendarContract.Events.TITLE,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DTEND,
            CalendarContract.Events.ALL_DAY,
            CalendarContract.Events.EVENT_LOCATION,
            CalendarContract.Events.DESCRIPTION,
        )

        // カレンダーIDフィルター（targetCalendarIds が空の場合はフィルターなしで全件取得）
        val (calendarFilter, calendarArgs) = if (targetCalendarIds.isNotEmpty()) {
            val placeholders = targetCalendarIds.joinToString(", ") { "?" }
            " AND ${CalendarContract.Events.CALENDAR_ID} IN ($placeholders)" to targetCalendarIds
        } else {
            "" to emptyList()
        }

        val selection = "${CalendarContract.Events.DTSTART} >= ? AND " +
            "${CalendarContract.Events.DTSTART} <= ? AND " +
            "${CalendarContract.Events.DELETED} = 0$calendarFilter"

        val selectionArgs = (
            listOf(rangeStart.toString(), rangeEnd.toString()) + calendarArgs
        ).toTypedArray()

        val result = mutableListOf<CalendarEventItem>()
        context.contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selection,
            selectionArgs,
            "${CalendarContract.Events.DTSTART} ASC"
        )?.use { cursor ->
            val idIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events._ID)
            val calIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.CALENDAR_ID)
            val titleIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.TITLE)
            val startIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.DTSTART)
            val endIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.DTEND)
            val allDayIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.ALL_DAY)
            val locationIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.EVENT_LOCATION)
            val descIdx = cursor.getColumnIndexOrThrow(CalendarContract.Events.DESCRIPTION)
            while (cursor.moveToNext()) {
                val endMs = cursor.getLong(endIdx).takeIf { it > 0 }
                result += CalendarEventItem(
                    id = cursor.getLong(idIdx).toString(),
                    calendarId = cursor.getLong(calIdx).toString(),
                    title = cursor.getString(titleIdx) ?: "",
                    startTime = Instant.fromEpochMilliseconds(cursor.getLong(startIdx)),
                    endTime = endMs?.let { Instant.fromEpochMilliseconds(it) },
                    isAllDay = cursor.getInt(allDayIdx) == 1,
                    location = cursor.getString(locationIdx),
                    notes = cursor.getString(descIdx),
                )
            }
        }
        // 最大5件に絞る（Windows版と同様の制限）
        return result.take(5)
    }

    // 全 RSS ソースからニュースを取得する
    private suspend fun fetchAllNews(rssSources: List<String>): List<NewsTopicItem> {
        if (rssSources.isEmpty()) return emptyList()
        return rssSources.flatMap { url ->
            try {
                fetchRssFeed(url)
            } catch (_: Exception) {
                emptyList()
            }
        }
    }

    // rssparser を使って RSS フィードを取得・パースしてニューストピック一覧を返す
    private suspend fun fetchRssFeed(url: String): List<NewsTopicItem> {
        readRssCache(url, allowExpired = false)?.let { return it }

        return try {
            val items = fetchRssFeedFromNetwork(url)
            writeRssCache(url, items)
            items
        } catch (e: Exception) {
            readRssCache(url, allowExpired = true) ?: throw e
        }
    }

    private suspend fun fetchRssFeedFromNetwork(url: String): List<NewsTopicItem> {
        val channel = rssParser.getRssChannel(url)
        return channel.items.mapNotNull { item ->
            val title = item.title ?: return@mapNotNull null
            val id = item.guid?.ifEmpty { null } ?: item.link ?: title
            val pubDate = parseRssDate(item.pubDate)
            // RSS の media:content / enclosure から画像 URL を取得し、なければ OGP を試みる
            val ogpImageUrl = item.image ?: fetchOgpImageUrl(item)
            NewsTopicItem(
                id = id,
                title = title,
                summary = item.description?.let { stripHtml(it) }?.takeIf { it.isNotEmpty() },
                url = item.link?.takeIf { it.isNotEmpty() },
                publishedAt = pubDate,
                ogpImageUrl = ogpImageUrl,
            )
        }
    }

    // RSS 取得結果を1時間キャッシュする。キャッシュはプロセス終了後も残るよう cacheDir に保存する。
    private suspend fun readRssCache(url: String, allowExpired: Boolean): List<NewsTopicItem>? =
        withContext(Dispatchers.IO) {
            val cacheFile = rssCacheFile(url)
            if (!cacheFile.exists() || cacheFile.length() == 0L) return@withContext null

            runCatching {
                val entry = cacheJson.decodeFromString<RssFeedCacheEntry>(cacheFile.readText())
                val ageMillis = Clock.System.now().toEpochMilliseconds() - entry.fetchedAtEpochMillis
                if (!allowExpired && ageMillis > RSS_CACHE_TTL.inWholeMilliseconds) {
                    null
                } else {
                    entry.items
                }
            }.getOrNull()
        }

    private suspend fun writeRssCache(url: String, items: List<NewsTopicItem>) =
        withContext(Dispatchers.IO) {
            runCatching {
                val cacheFile = rssCacheFile(url)
                cacheFile.parentFile?.mkdirs()
                val tempFile = File(cacheFile.parentFile, "${cacheFile.name}.tmp")
                val entry = RssFeedCacheEntry(
                    fetchedAtEpochMillis = Clock.System.now().toEpochMilliseconds(),
                    items = items,
                )
                tempFile.writeText(cacheJson.encodeToString(entry))
                if (!tempFile.renameTo(cacheFile)) {
                    tempFile.copyTo(cacheFile, overwrite = true)
                    tempFile.delete()
                }
            }
        }

    private fun rssCacheFile(url: String): File =
        File(File(context.cacheDir, "rss-cache"), "${url.sha256()}.json")

    // jsoup を使って記事ページの OGP 画像 URL を取得する（rssparser がメディアを返さなかった場合のフォールバック）
    private suspend fun fetchOgpImageUrl(item: RssItem): String? {
        val articleUrl = item.link?.takeIf { it.isNotEmpty() } ?: return null
        return withContext(Dispatchers.IO) {
            try {
                val request = Request.Builder()
                    .url(articleUrl)
                    .header("User-Agent", "WondayWall/1.0")
                    .build()
                val html = httpClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) return@withContext null
                    response.body?.string() ?: return@withContext null
                }
                val doc = Jsoup.parse(html, articleUrl)
                // og:image:secure_url を優先し、なければ og:image を使う
                doc.select("meta[property=og:image:secure_url]").attr("content")
                    .takeIf { it.isNotEmpty() }
                    ?: doc.select("meta[property=og:image]").attr("content")
                        .takeIf { it.isNotEmpty() }
            } catch (_: Exception) {
                null
            }
        }
    }

    // jsoup を使って HTML タグを除去する
    private fun stripHtml(html: String): String =
        Jsoup.parse(html).text()

    private fun containsToken(source: String, token: String): Boolean =
        source.split(Regex("\\s+"))
            .any { it.equals(token, ignoreCase = true) }

    private fun isFeedContentType(contentType: String): Boolean =
        contentType.contains("application/rss+xml", ignoreCase = true)
            || contentType.contains("application/atom+xml", ignoreCase = true)

    private fun isLikelyRssUrl(uri: URI): Boolean {
        val path = uri.path ?: ""
        if (path.endsWith(".xml", ignoreCase = true)
            || path.endsWith(".rss", ignoreCase = true)
            || path.endsWith(".atom", ignoreCase = true)
        ) {
            return true
        }

        val query = uri.query ?: ""
        return path.contains("feed", ignoreCase = true)
            || path.contains("rss", ignoreCase = true)
            || path.contains("atom", ignoreCase = true)
            || query.contains("feed", ignoreCase = true)
            || query.contains("rss", ignoreCase = true)
            || query.contains("atom", ignoreCase = true)
    }

    // RSS の日付文字列をパースする
    private fun parseRssDate(dateStr: String?): Instant {
        if (dateStr.isNullOrEmpty()) return Clock.System.now()
        return try {
            // ISO 8601 形式の場合
            Instant.parse(dateStr)
        } catch (_: Exception) {
            try {
                // RFC 822 形式（典型的な RSS 形式）のパース
                val sdf = java.text.SimpleDateFormat(
                    "EEE, dd MMM yyyy HH:mm:ss zzz", java.util.Locale.ENGLISH
                )
                val date = sdf.parse(dateStr)
                if (date != null) Instant.fromEpochMilliseconds(date.time) else Clock.System.now()
            } catch (_: Exception) {
                Clock.System.now()
            }
        }
    }

    // CalendarEventItem を PromptCalendarEvent に変換する
    private fun CalendarEventItem.toPromptCalendarEvent(): PromptCalendarEvent {
        val now = Clock.System.now()
        val diffHours = (startTime - now).inWholeHours
        val proximityTag = when {
            diffHours < 24 -> "today"
            diffHours < 48 -> "tomorrow"
            else -> "in ${(startTime - now).inWholeDays} days"
        }
        return PromptCalendarEvent(
            id = id,
            title = title,
            proximityTag = proximityTag,
            startTime = startTime,
            endTime = endTime,
            location = location,
            description = notes,
        )
    }

    // NewsTopicItem を PromptNewsTopic に変換する
    private fun NewsTopicItem.toPromptNewsTopic() = PromptNewsTopic(
        id = id,
        title = title,
        summary = summary,
        url = url,
        publishedAt = publishedAt,
        ogpImageUrl = ogpImageUrl,
    )

    private fun String.sha256(): String =
        MessageDigest.getInstance("SHA-256")
            .digest(toByteArray(Charsets.UTF_8))
            .joinToString("") { byte ->
                (byte.toInt() and 0xff).toString(16).padStart(2, '0')
            }

    companion object {
        private val RSS_CACHE_TTL = 1.hours
    }
}

@Serializable
private data class RssFeedCacheEntry(
    val fetchedAtEpochMillis: Long,
    val items: List<NewsTopicItem>,
)
