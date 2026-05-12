package com.studiofreesia.wondaywall.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.provider.CalendarContract
import androidx.core.content.ContextCompat
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.CalendarSourceItem
import com.studiofreesia.wondaywall.models.ContextBuildResult
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.models.PromptCalendarEvent
import com.studiofreesia.wondaywall.models.PromptContext
import com.studiofreesia.wondaywall.models.PromptNewsTopic
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import okhttp3.OkHttpClient
import okhttp3.Request
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserFactory
import java.io.StringReader
import java.util.concurrent.TimeUnit
import kotlin.time.Duration.Companion.days
import kotlin.time.Duration.Companion.hours

// 画像生成に使うコンテキストを構築するサービス
class ContextService(
    private val context: Context,
    private val appConfigService: AppConfigService,
) {
    private val httpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()

    // PromptContext を構築して返す
    suspend fun buildPromptContext(baseImagePath: String? = null): ContextBuildResult {
        val config = appConfigService.getConfig()

        // カレンダーイベントを取得する
        val calendarEvents = getCalendarEvents(config.targetCalendarIds)

        // ニュースを取得する（最大10件）
        val newsTopics = fetchAllNews(config.rssSources).take(10)

        // 前回壁紙をベースにする設定の場合のみパスを渡す
        val effectiveBasePath = if (config.useCurrentWallpaperAsBase) baseImagePath else null

        val promptContext = PromptContext(
            calendarEvents = calendarEvents.map { it.toPromptCalendarEvent() },
            newsTopics = newsTopics.map { it.toPromptNewsTopic() },
            additionalConstraints = config.userPrompt,
            baseImagePath = effectiveBasePath,
        )

        return ContextBuildResult(
            promptContext = promptContext,
            calendarEvents = calendarEvents,
            newsTopics = newsTopics,
        )
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

        // カレンダーIDフィルター
        val calendarFilter = if (targetCalendarIds.isNotEmpty()) {
            " AND (" + targetCalendarIds.joinToString(" OR ") {
                "${CalendarContract.Events.CALENDAR_ID} = ?"
            } + ")"
        } else ""

        val selection = "${CalendarContract.Events.DTSTART} >= ? AND " +
            "${CalendarContract.Events.DTSTART} <= ? AND " +
            "${CalendarContract.Events.DELETED} = 0$calendarFilter"

        val selectionArgs = (
            listOf(rangeStart.toString(), rangeEnd.toString()) + targetCalendarIds
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
            } catch (e: Exception) {
                emptyList()
            }
        }
    }

    // RSS フィードを取得してパースする
    private suspend fun fetchRssFeed(url: String): List<NewsTopicItem> = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(url)
            .header("User-Agent", "WondayWall/1.0")
            .build()
        val body = httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) return@withContext emptyList()
            response.body?.string() ?: return@withContext emptyList()
        }
        parseRss(body)
    }

    // RSS XML をパースしてニューストピック一覧を返す
    private fun parseRss(xml: String): List<NewsTopicItem> {
        val result = mutableListOf<NewsTopicItem>()
        try {
            val factory = XmlPullParserFactory.newInstance()
            factory.isNamespaceAware = true
            val parser = factory.newPullParser()
            parser.setInput(StringReader(xml))

            var inItem = false
            var title = ""
            var link = ""
            var description = ""
            var pubDate = ""
            var guid = ""
            var mediaUrl: String? = null
            var enclosureUrl: String? = null
            var currentTag = ""

            var eventType = parser.eventType
            while (eventType != XmlPullParser.END_DOCUMENT) {
                when (eventType) {
                    XmlPullParser.START_TAG -> {
                        currentTag = parser.name ?: ""
                        when (currentTag) {
                            "item" -> {
                                inItem = true
                                title = ""; link = ""; description = ""; pubDate = ""
                                guid = ""; mediaUrl = null; enclosureUrl = null
                            }
                            "enclosure" -> {
                                val type = parser.getAttributeValue(null, "type") ?: ""
                                if (type.startsWith("image/")) {
                                    enclosureUrl = parser.getAttributeValue(null, "url")
                                }
                            }
                            "content", "thumbnail" -> {
                                // media:content または media:thumbnail
                                val ns = parser.namespace ?: ""
                                if (ns.contains("media")) {
                                    val candidate = parser.getAttributeValue(null, "url")
                                    if (candidate != null && mediaUrl == null) {
                                        mediaUrl = candidate
                                    }
                                }
                            }
                        }
                    }
                    XmlPullParser.TEXT -> {
                        if (inItem) {
                            val text = parser.text?.trim() ?: ""
                            when (currentTag) {
                                "title" -> title = text
                                "link" -> if (link.isEmpty()) link = text
                                "description" -> if (description.isEmpty()) description = text
                                "pubDate", "published", "updated" -> pubDate = text
                                "guid" -> guid = text
                            }
                        }
                    }
                    XmlPullParser.END_TAG -> {
                        if (parser.name == "item" && inItem) {
                            inItem = false
                            val id = guid.ifEmpty { link }.ifEmpty { title }
                            val parsedDate = parseRssDate(pubDate)
                            if (title.isNotEmpty()) {
                                result += NewsTopicItem(
                                    id = id,
                                    title = title,
                                    summary = description.takeIf { it.isNotEmpty() },
                                    url = link.takeIf { it.isNotEmpty() },
                                    publishedAt = parsedDate,
                                    ogpImageUrl = mediaUrl ?: enclosureUrl,
                                )
                            }
                        }
                        currentTag = ""
                    }
                }
                eventType = parser.next()
            }
        } catch (e: Exception) {
            // パースエラーは無視して取得済み分を返す
        }
        return result
    }

    // RSS の日付文字列をパースする
    private fun parseRssDate(dateStr: String): Instant {
        if (dateStr.isEmpty()) return Clock.System.now()
        return try {
            // ISO 8601 形式の場合
            Instant.parse(dateStr)
        } catch (e: Exception) {
            try {
                // RFC 822 形式（典型的な RSS 形式）のパース
                val sdf = java.text.SimpleDateFormat(
                    "EEE, dd MMM yyyy HH:mm:ss zzz", java.util.Locale.ENGLISH
                )
                val date = sdf.parse(dateStr)
                if (date != null) Instant.fromEpochMilliseconds(date.time)
                else Clock.System.now()
            } catch (e2: Exception) {
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
}
