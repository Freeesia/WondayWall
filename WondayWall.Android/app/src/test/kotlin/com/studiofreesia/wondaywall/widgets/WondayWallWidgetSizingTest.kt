package com.studiofreesia.wondaywall.widgets

import android.content.Context
import android.content.res.Configuration
import android.util.TypedValue
import androidx.test.core.app.ApplicationProvider
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import kotlinx.datetime.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(manifest = Config.NONE, sdk = [36])
class WondayWallWidgetSizingTest {
    @Test
    fun overflowedItemsAlwaysFitWithinHeightBudget() {
        val context = contextWithFontScale(1.3f)
        val state = widgetState(longNewsTitles = true)
        val cases = listOf(
            Triple(234, 99, true),
            Triple(234, 120, true),
            Triple(218, 188, false),
            Triple(218, 240, false),
            Triple(218, 320, false),
            Triple(218, 400, false),
        )

        cases.forEach { (widthDp, heightDp, compact) ->
            val items = visibleInfoItems(context, state, widthDp, heightDp, compact)
            assertFitsWithinHeightBudget(context, items, widthDp, heightDp, compact)
            if (items.size < displayedInfoItemCount(state) && canFitFirstItemAndMore(context, state, widthDp, heightDp, compact)) {
                    assertTrue("overflow should end with More row", hasMoreRow(items))
            }
        }
    }

    @Test
    fun tallerWidgetNeverShowsFewerRealItems() {
        val context = contextWithFontScale(1.0f)
        val state = widgetState(longNewsTitles = true)
        val heights = listOf(99, 120, 150, 188, 240, 320, 400)
        val counts = heights.map { heightDp ->
            countRealItems(visibleInfoItems(context, state, 218, heightDp, compact = false))
        }

        counts.zipWithNext().forEachIndexed { index, (before, after) ->
            assertTrue("height ${heights[index]}dp -> ${heights[index + 1]}dp should not reduce item count", after >= before)
        }
        assertTrue("taller widget should show more items somewhere", counts.zipWithNext().any { (before, after) -> after > before })
    }

    @Test
    fun wrappedNewsRowMeasuresAboveMinimumHeight() {
        val context = contextWithFontScale(1.0f)
        val longState = widgetState(longNewsTitles = true)
        val longNewsItem = orderedInfoItems(longState).first { it.javaClass.simpleName == "News" }

        val measuredHeightPx = measureItemHeight(context, longNewsItem, dpToPx(context, 218), compact = false)
        val minimumHeightPx = dpToPx(context, 46)

        assertTrue("wrapped news row should exceed minimum height", measuredHeightPx > minimumHeightPx)
    }

    @Test
    fun representativeCompactWidgetShowsMoreWhenTruncated() {
        val largeFontContext = contextWithFontScale(1.3f)
        val state = widgetState(longNewsTitles = true)
        val items = visibleInfoItems(largeFontContext, state, 234, 99, compact = true)
        val allItems = orderedInfoItems(state)
        val firstHeight = measureItemHeight(largeFontContext, allItems.first(), dpToPx(largeFontContext, 234), compact = true)
        val moreHeight = measureItemHeight(largeFontContext, createMoreRowItem(), dpToPx(largeFontContext, 234), compact = true)

        assertTrue("compact min-height widget should truncate", countRealItems(items) < displayedInfoItemCount(state))
        assertTrue(
            "compact min-height widget should show More row: first=${firstHeight}px more=${moreHeight}px items=${items.map { it.javaClass.simpleName }}",
            hasMoreRow(items),
        )
    }

    @Test
    fun representativeTallWidgetShowsMoreWhenTruncated() {
        val context = contextWithFontScale(1.3f)
        val state = widgetState(longNewsTitles = true)
        val items = visibleInfoItems(context, state, 218, 400, compact = false)

        assertTrue("tall widget should still truncate with long content", countRealItems(items) < displayedInfoItemCount(state))
        assertTrue("tall widget should show More row when truncated", hasMoreRow(items))
        assertFitsWithinHeightBudget(context, items, 218, 400, compact = false)
    }

    @Test
    fun hiddenSourceItemsStillShowMoreWhenDisplayedRowsAllFit() {
        val context = contextWithFontScale(1.0f)
        val state = widgetState(
            longNewsTitles = false,
            hasHiddenCalendarEvents = true,
            hasHiddenNewsTopics = true,
        )
        val items = visibleInfoItems(context, state, 218, 1200, compact = false)

        assertEquals(displayedInfoItemCount(state) + 1, items.size)
        assertTrue("hidden source items should keep More row visible", hasMoreRow(items))
        assertFitsWithinHeightBudget(context, items, 218, 1200, compact = false)
    }

    @Test
    fun veryTallWidgetShowsAllItemsWithoutMore() {
        val context = contextWithFontScale(1.3f)
        val state = widgetState(longNewsTitles = true)
        val items = visibleInfoItems(context, state, 218, 1200, compact = false)

        assertEquals(displayedInfoItemCount(state), items.size)
        assertFalse("very tall widget should not show More row", hasMoreRow(items))
        assertFitsWithinHeightBudget(context, items, 218, 1200, compact = false)
    }

    private fun contextWithFontScale(fontScale: Float): Context {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val configuration = Configuration(base.resources.configuration).apply {
            this.fontScale = fontScale
        }
        return base.createConfigurationContext(configuration)
    }

    private fun widgetState(longNewsTitles: Boolean): WidgetDisplayState =
        WidgetDisplayState(
            status = WidgetSlotStatus.Processed,
            currentSlotStartedAtMillis = 0L,
            backgroundImage = null,
            canOpenGenerationConfirmation = false,
            usedCalendarEvents = (1..4).map { index ->
                CalendarEventItem(
                    id = "calendar-$index",
                    calendarId = "primary",
                    title = "予定タイトル$index",
                    startTime = Instant.parse("2026-06-13T0${index}:00:00Z"),
                    endTime = Instant.parse("2026-06-13T0${index}:30:00Z"),
                    isAllDay = false,
                    location = "会議室$index",
                    notes = null,
                )
            },
            usedNewsTopics = (1..8).map { index ->
                NewsTopicItem(
                    id = "news-$index",
                    title = if (longNewsTitles) {
                        "とても長いニュース見出しがここに入り、折り返し表示と高さ計算を確認するためのダミーテキストです $index"
                    } else {
                        "ニュース$index"
                    },
                    summary = null,
                    url = "https://example.com/$index",
                    publishedAt = Instant.parse("2026-06-13T1${index}:00:00Z"),
                    ogpImageUrl = null,
                )
            },
            hasHiddenInfoItems = false,
            faviconImages = emptyMap(),
        )

    private fun widgetState(
        longNewsTitles: Boolean,
        hasHiddenCalendarEvents: Boolean,
        hasHiddenNewsTopics: Boolean,
    ): WidgetDisplayState =
        widgetState(longNewsTitles = longNewsTitles).copy(
            hasHiddenInfoItems = hasHiddenCalendarEvents || hasHiddenNewsTopics,
        )

    private fun displayedInfoItemCount(state: WidgetDisplayState): Int =
        state.usedCalendarEvents.size + state.usedNewsTopics.size

    private fun orderedInfoItems(state: WidgetDisplayState): List<Any> {
        val method = widgetKtClass.declaredMethods.single { it.name == "orderedInfoItems" }.apply {
            isAccessible = true
        }
        @Suppress("UNCHECKED_CAST")
        return method.invoke(null, state) as List<Any>
    }

    private fun visibleInfoItems(
        context: Context,
        state: WidgetDisplayState,
        availableWidthDp: Int,
        availableHeightDp: Int,
        compact: Boolean,
    ): List<Any> {
        val method = widgetKtClass.declaredMethods.single { it.name == "visibleInfoItems" }.apply {
            isAccessible = true
        }
        @Suppress("UNCHECKED_CAST")
        return method.invoke(null, context, state, availableWidthDp, availableHeightDp, compact) as List<Any>
    }

    private fun hasMoreRow(items: List<Any>): Boolean =
        items.lastOrNull()?.javaClass?.simpleName == "More"

    private fun countRealItems(items: List<Any>): Int =
        items.count { it.javaClass.simpleName != "More" }

    private fun canFitFirstItemAndMore(
        context: Context,
        state: WidgetDisplayState,
        availableWidthDp: Int,
        availableHeightDp: Int,
        compact: Boolean,
    ): Boolean {
        val allItems = orderedInfoItems(state)
        val firstItem = allItems.first()
        val moreItem = allItems.firstOrNull { it.javaClass.simpleName == "More" } ?: createMoreRowItem()
        val rowWidthPx = dpToPx(context, availableWidthDp)
        val dividerHeightPx = dpToPx(context, 1).coerceAtLeast(1)
        val totalHeightPx = measureItemHeight(context, firstItem, rowWidthPx, compact) +
            dividerHeightPx +
            measureItemHeight(context, moreItem, rowWidthPx, compact)
        return totalHeightPx <= dpToPx(context, availableHeightDp)
    }

    private fun createMoreRowItem(): Any {
        val moreClass = Class.forName("com.studiofreesia.wondaywall.widgets.WidgetInfoListItem\$More")
        return moreClass.getField("INSTANCE").get(null) as Any
    }

    private fun assertFitsWithinHeightBudget(
        context: Context,
        items: List<Any>,
        availableWidthDp: Int,
        availableHeightDp: Int,
        compact: Boolean,
    ) {
        val rowWidthPx = dpToPx(context, availableWidthDp)
        val dividerHeightPx = dpToPx(context, 1).coerceAtLeast(1)
        val totalHeightPx = items.sumOf { measureItemHeight(context, it, rowWidthPx, compact) } +
            dividerHeightPx * (items.size - 1).coerceAtLeast(0)

        assertTrue(
            "items should fit within ${availableHeightDp}dp but were ${totalHeightPx}px",
            totalHeightPx <= dpToPx(context, availableHeightDp),
        )
    }

    private fun measureItemHeight(
        context: Context,
        item: Any,
        rowWidthPx: Int,
        compact: Boolean,
    ): Int {
        val method = widgetKtClass.declaredMethods.single { it.name == "measureInfoItemHeight" }.apply {
            isAccessible = true
        }
        return method.invoke(null, context, item, rowWidthPx, compact) as Int
    }

    private fun dpToPx(context: Context, dp: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            context.resources.displayMetrics,
        ).toInt()

    private companion object {
        val widgetKtClass: Class<*> =
            Class.forName("com.studiofreesia.wondaywall.widgets.WondayWallWidgetKt")
    }
}
