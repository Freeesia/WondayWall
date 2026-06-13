package com.studiofreesia.wondaywall.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.Build
import android.net.Uri
import android.util.TypedValue
import android.view.LayoutInflater
import android.view.View
import android.widget.RemoteViews
import android.widget.TextView
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.studiofreesia.wondaywall.R
import com.studiofreesia.wondaywall.MainActivity
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

private enum class WidgetDisplaySize {
    Small,
    Medium,
    Large,
}

class WondayWallWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = WidgetStateRepository(context).load(includeFaviconImages = true)
        provideContent {
            WondayWallWidgetContent(
                context = context,
                state = state,
            )
        }
    }
}

class WondayWallWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WondayWallWidget()
}

@Composable
private fun WondayWallWidgetContent(
    context: Context,
    state: WidgetDisplayState,
) {
    val size = LocalSize.current
    val displaySize = when {
        size.width < 180.dp -> WidgetDisplaySize.Small
        size.height >= 220.dp -> WidgetDisplaySize.Large
        else -> WidgetDisplaySize.Medium
    }

    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ColorProvider(Color(0xFF263238))),
    ) {
        state.backgroundImage?.let { image ->
            Image(
                provider = ImageProvider(image),
                contentDescription = "最新の壁紙",
                contentScale = ContentScale.Crop,
                modifier = GlanceModifier.fillMaxSize(),
            )
        }
        Box(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ColorProvider(scrimColor(state))),
        ) {
            if (state.canOpenGenerationConfirmation) {
                CenteredGenerateContent(context, state, displaySize)
            } else {
                when (displaySize) {
                    WidgetDisplaySize.Small -> SmallWidgetContent(context, state)
                    WidgetDisplaySize.Medium -> MediumWidgetContent(
                        context = context,
                        state = state,
                        widgetWidthDp = size.width.value.roundToInt(),
                        widgetHeightDp = size.height.value.roundToInt(),
                    )
                    WidgetDisplaySize.Large -> LargeWidgetContent(
                        context = context,
                        state = state,
                        widgetWidthDp = size.width.value.roundToInt(),
                        widgetHeightDp = size.height.value.roundToInt(),
                    )
                }
            }
        }
    }
}

private fun scrimColor(state: WidgetDisplayState): Color =
    if (state.status == WidgetSlotStatus.Processed) {
        Color(0x26000000)
    } else {
        Color(0x88000000)
    }

@Composable
private fun CenteredGenerateContent(
    context: Context,
    state: WidgetDisplayState,
    size: WidgetDisplaySize,
) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(12.dp),
        contentAlignment = Alignment.Center,
    ) {
        GenerateAction(
            context = context,
            state = state,
            compact = size == WidgetDisplaySize.Small,
        )
    }
}

@Composable
private fun SmallWidgetContent(
    context: Context,
    state: WidgetDisplayState,
) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(12.dp),
        contentAlignment = if (shouldShowSmallNewsButton(state)) {
            Alignment.Center
        } else {
            Alignment.BottomStart
        },
    ) {
        when {
            shouldShowSmallNewsButton(state) -> SmallNewsButton(context)
            shouldShowStatus(state) -> StatusLabel(state)
        }
    }
}

@Composable
private fun MediumWidgetContent(
    context: Context,
    state: WidgetDisplayState,
    widgetWidthDp: Int,
    widgetHeightDp: Int,
) {
    val verticalPadding = 8
    val horizontalPadding = 8
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(vertical = verticalPadding.dp, horizontal = horizontalPadding.dp),
    ) {
        if (shouldShowStatus(state)) {
            StatusLabel(state)
            Spacer(GlanceModifier.height(8.dp))
        }
        if (shouldShowInfo(state)) {
            InfoContent(
                context = context,
                state = state,
                compact = true,
                widgetWidthDp = widgetWidthDp,
                widgetHeightDp = widgetHeightDp,
                horizontalPaddingDp = horizontalPadding * 2,
                verticalPaddingDp = verticalPadding * 2,
            )
        }
    }
}

@Composable
private fun LargeWidgetContent(
    context: Context,
    state: WidgetDisplayState,
    widgetWidthDp: Int,
    widgetHeightDp: Int,
) {
    val verticalPadding = 16
    val horizontalPadding = 16
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(vertical = verticalPadding.dp, horizontal = horizontalPadding.dp),
    ) {
        if (shouldShowStatus(state)) {
            StatusLabel(state)
            Spacer(GlanceModifier.height(10.dp))
        }
        if (shouldShowInfo(state)) {
            InfoContent(
                context = context,
                state = state,
                compact = false,
                widgetWidthDp = widgetWidthDp,
                widgetHeightDp = widgetHeightDp,
                horizontalPaddingDp = horizontalPadding * 2,
                verticalPaddingDp = verticalPadding * 2,
            )
        }
    }
}

@Composable
private fun StatusLabel(state: WidgetDisplayState) {
    Text(
        text = statusText(state),
        maxLines = 1,
        style = TextStyle(
            color = ColorProvider(Color.White),
            fontWeight = FontWeight.Bold,
            fontSize = 13.sp,
        ),
    )
}

@Composable
private fun SmallNewsButton(context: Context) {
    Text(
        text = "本日のニュース",
        maxLines = 1,
        style = TextStyle(
            color = ColorProvider(Color.White),
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
        ),
        modifier = GlanceModifier
            .background(ColorProvider(Color(0x99000000)))
            .cornerRadius(50.dp)
            .padding(horizontal = 12.dp, vertical = 8.dp)
            .clickable(actionStartActivity(newsHomeIntent(context))),
    )
}

@Composable
private fun GenerateAction(
    context: Context,
    state: WidgetDisplayState,
    compact: Boolean,
) {
    Text(
        text = if (compact) "生成" else "壁紙生成",
        maxLines = 1,
        style = TextStyle(
            color = ColorProvider(Color.White),
            fontWeight = FontWeight.Bold,
            fontSize = if (compact) 18.sp else 20.sp,
            textAlign = TextAlign.Center,
        ),
        modifier = GlanceModifier
            .background(ColorProvider(Color(0xFF3F51B5)))
            .cornerRadius(50.dp)
            .padding(horizontal = if (compact) 18.dp else 22.dp, vertical = if (compact) 12.dp else 14.dp)
            .clickable(actionStartActivity(generateIntent(context, state.currentSlotStartedAtMillis))),
    )
}

@OptIn(ExperimentalGlanceRemoteViewsApi::class)
@Composable
private fun InfoContent(
    context: Context,
    state: WidgetDisplayState,
    compact: Boolean,
    widgetWidthDp: Int,
    widgetHeightDp: Int,
    horizontalPaddingDp: Int,
    verticalPaddingDp: Int,
) {
    val availableWidth = (widgetWidthDp - horizontalPaddingDp).coerceAtLeast(120)
    val availableHeight = (widgetHeightDp - verticalPaddingDp).coerceAtLeast(96)
    val items = visibleInfoItems(
        context = context,
        state = state,
        availableWidthDp = availableWidth,
        availableHeightDp = availableHeight,
        compact = compact,
    )

    AndroidRemoteViews(
        remoteViews = infoListRemoteViews(context, state, compact, items),
        modifier = GlanceModifier
            .fillMaxWidth()
            .height(availableHeight.dp),
    )
}

private fun shouldShowStatus(state: WidgetDisplayState): Boolean =
    state.status != WidgetSlotStatus.Processed && state.status != WidgetSlotStatus.Pending

private fun shouldShowInfo(state: WidgetDisplayState): Boolean =
    state.status == WidgetSlotStatus.Processed &&
        (state.usedCalendarEvents.isNotEmpty() || state.usedNewsTopics.isNotEmpty())

private fun shouldShowSmallNewsButton(state: WidgetDisplayState): Boolean =
    state.status == WidgetSlotStatus.Processed

private const val INFO_DIVIDER_HEIGHT_DP = 1
private const val NEWS_TITLE_TEXT_SIZE_SP = 13f
private const val NEWS_DATE_TEXT_SIZE_SP = 10f
private const val CALENDAR_TITLE_TEXT_SIZE_SP = 13f
private const val CALENDAR_SUBTITLE_TEXT_SIZE_SP = 10.5f
private const val MORE_TEXT_TEXT_SIZE_SP = 13f
private const val MORE_ARROW_TEXT_SIZE_SP = 16f

private data class WidgetRowLayoutParams(
    val horizontalPaddingDp: Int,
    val verticalPaddingDp: Int,
    val minHeightDp: Int,
)

private fun newsRowLayoutParams(compact: Boolean): WidgetRowLayoutParams =
    WidgetRowLayoutParams(
        horizontalPaddingDp = if (compact) 8 else 12,
        verticalPaddingDp = if (compact) 3 else 5,
        minHeightDp = if (compact) 40 else 46,
    )

private fun calendarRowLayoutParams(compact: Boolean): WidgetRowLayoutParams =
    WidgetRowLayoutParams(
        horizontalPaddingDp = if (compact) 8 else 12,
        verticalPaddingDp = if (compact) 5 else 8,
        minHeightDp = if (compact) 40 else 46,
    )

private fun moreRowLayoutParams(compact: Boolean): WidgetRowLayoutParams =
    WidgetRowLayoutParams(
        horizontalPaddingDp = if (compact) 8 else 12,
        verticalPaddingDp = if (compact) 5 else 8,
        minHeightDp = if (compact) 32 else 40,
    )

private fun infoListRemoteViews(
    context: Context,
    state: WidgetDisplayState,
    compact: Boolean,
    items: List<WidgetInfoListItem>,
): RemoteViews =
    RemoteViews(context.packageName, R.layout.wondaywall_widget_info_list).apply {
        removeAllViews(R.id.wondaywall_widget_info_list_container)
        items.forEachIndexed { index, item ->
            if (index > 0) {
                addInfoDivider(context, this)
            }
            addView(
                R.id.wondaywall_widget_info_list_container,
                when (item) {
                    is WidgetInfoListItem.Calendar -> calendarRow(context, item.event, compact)
                    WidgetInfoListItem.More -> moreRow(context, compact)
                    is WidgetInfoListItem.News -> newsRow(context, item.news, state.faviconImages[item.news.id], compact)
                },
            )
        }
    }

private fun visibleInfoItems(
    context: Context,
    state: WidgetDisplayState,
    availableWidthDp: Int,
    availableHeightDp: Int,
    compact: Boolean,
): List<WidgetInfoListItem> {
    val allItems = orderedInfoItems(state)
    if (allItems.isEmpty()) {
        return emptyList()
    }

    val availableWidthPx = dpToPx(context, availableWidthDp)
    val availableHeightPx = dpToPx(context, availableHeightDp)
    val dividerHeightPx = dpToPx(context, INFO_DIVIDER_HEIGHT_DP).coerceAtLeast(1)
    val itemHeightsPx = allItems.map { item ->
        measureInfoItemHeight(context, item, availableWidthPx, compact)
    }
    if (totalListHeightPx(itemHeightsPx, dividerHeightPx) <= availableHeightPx) {
        return allItems
    }

    val moreHeightPx = measureInfoItemHeight(context, WidgetInfoListItem.More, availableWidthPx, compact)
    var usedHeightPx = 0
    var visibleCount = 0
    for (itemHeightPx in itemHeightsPx) {
        val nextUsedHeightPx = if (visibleCount == 0) {
            itemHeightPx
        } else {
            usedHeightPx + dividerHeightPx + itemHeightPx
        }
        val totalWithMorePx = nextUsedHeightPx + dividerHeightPx + moreHeightPx
        if (totalWithMorePx > availableHeightPx) {
            break
        }
        usedHeightPx = nextUsedHeightPx
        visibleCount += 1
    }

    if (visibleCount == 0) {
        return if (moreHeightPx <= availableHeightPx) {
            listOf(WidgetInfoListItem.More)
        } else {
            listOf(allItems.first())
        }
    }

    return allItems.take(visibleCount) + WidgetInfoListItem.More
}

private fun orderedInfoItems(state: WidgetDisplayState): List<WidgetInfoListItem> {
    val calendarItems = state.usedCalendarEvents.map(WidgetInfoListItem::Calendar)
    val newsItems = state.usedNewsTopics.map(WidgetInfoListItem::News)
    if (calendarItems.isEmpty()) return newsItems
    if (newsItems.isEmpty()) return calendarItems

    return buildList {
        add(calendarItems.first())
        addAll(newsItems)
        addAll(calendarItems.drop(1))
    }
}

private sealed class WidgetInfoListItem {
    data class Calendar(val event: CalendarEventItem) : WidgetInfoListItem()
    data class News(val news: NewsTopicItem) : WidgetInfoListItem()
    object More : WidgetInfoListItem()
}

private fun totalListHeightPx(itemHeightsPx: List<Int>, dividerHeightPx: Int): Int {
    if (itemHeightsPx.isEmpty()) {
        return 0
    }
    return itemHeightsPx.sum() + dividerHeightPx * (itemHeightsPx.size - 1)
}

private fun measureInfoItemHeight(
    context: Context,
    item: WidgetInfoListItem,
    rowWidthPx: Int,
    compact: Boolean,
): Int =
    when (item) {
        is WidgetInfoListItem.Calendar -> measureCalendarRowHeight(context, item.event, rowWidthPx, compact)
        WidgetInfoListItem.More -> measureMoreRowHeight(context, rowWidthPx, compact)
        is WidgetInfoListItem.News -> measureNewsRowHeight(context, item.news, rowWidthPx, compact)
    }

// RemoteViews 自体はレイアウト後の高さを返せないため、同じ行レイアウトをオフスクリーンで測って表示件数を決める。
private fun measureNewsRowHeight(
    context: Context,
    item: NewsTopicItem,
    rowWidthPx: Int,
    compact: Boolean,
): Int =
    measureRowHeight(context, R.layout.wondaywall_widget_news_row, rowWidthPx) { view ->
        val params = newsRowLayoutParams(compact)
        applyRowLayoutParams(context, view.findViewById(R.id.wondaywall_widget_news_row_root), params)
        view.findViewById<TextView>(R.id.wondaywall_widget_news_title).apply {
            text = item.title
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NEWS_TITLE_TEXT_SIZE_SP)
            maxLines = 2
        }
        view.findViewById<TextView>(R.id.wondaywall_widget_news_date).apply {
            text = formatNewsPublishedAt(item)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, NEWS_DATE_TEXT_SIZE_SP)
        }
    }

private fun measureCalendarRowHeight(
    context: Context,
    item: CalendarEventItem,
    rowWidthPx: Int,
    compact: Boolean,
): Int =
    measureRowHeight(context, R.layout.wondaywall_widget_calendar_row, rowWidthPx) { view ->
        val params = calendarRowLayoutParams(compact)
        applyRowLayoutParams(context, view.findViewById(R.id.wondaywall_widget_calendar_row_root), params)
        view.findViewById<TextView>(R.id.wondaywall_widget_calendar_title).apply {
            text = item.title
            setTextSize(TypedValue.COMPLEX_UNIT_SP, CALENDAR_TITLE_TEXT_SIZE_SP)
        }
        view.findViewById<TextView>(R.id.wondaywall_widget_calendar_subtitle).apply {
            text = calendarSubtitle(item)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, CALENDAR_SUBTITLE_TEXT_SIZE_SP)
        }
    }

private fun measureMoreRowHeight(
    context: Context,
    rowWidthPx: Int,
    compact: Boolean,
): Int =
    measureRowHeight(context, R.layout.wondaywall_widget_more_row, rowWidthPx) { view ->
        val params = moreRowLayoutParams(compact)
        applyRowLayoutParams(context, view.findViewById(R.id.wondaywall_widget_more_row_root), params)
        view.findViewById<TextView>(R.id.wondaywall_widget_more_text)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, MORE_TEXT_TEXT_SIZE_SP)
        view.findViewById<TextView>(R.id.wondaywall_widget_more_arrow)
            .setTextSize(TypedValue.COMPLEX_UNIT_SP, MORE_ARROW_TEXT_SIZE_SP)
    }

private fun measureRowHeight(
    context: Context,
    layoutId: Int,
    rowWidthPx: Int,
    bind: (View) -> Unit,
): Int {
    val view = LayoutInflater.from(context).inflate(layoutId, null, false)
    bind(view)
    val widthSpec = View.MeasureSpec.makeMeasureSpec(rowWidthPx, View.MeasureSpec.EXACTLY)
    val heightSpec = View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED)
    view.measure(widthSpec, heightSpec)
    return view.measuredHeight
}

private fun applyRowLayoutParams(
    context: Context,
    view: View,
    params: WidgetRowLayoutParams,
) {
    val horizontalPaddingPx = dpToPx(context, params.horizontalPaddingDp)
    val verticalPaddingPx = dpToPx(context, params.verticalPaddingDp)
    view.setPadding(horizontalPaddingPx, verticalPaddingPx, horizontalPaddingPx, verticalPaddingPx)
    view.minimumHeight = dpToPx(context, params.minHeightDp)
}

private fun newsRow(
    context: Context,
    item: NewsTopicItem,
    favicon: Bitmap?,
    compact: Boolean,
): RemoteViews =
    RemoteViews(context.packageName, R.layout.wondaywall_widget_news_row).apply {
        val params = newsRowLayoutParams(compact)
        setViewPadding(
            R.id.wondaywall_widget_news_row_root,
            dpToPx(context, params.horizontalPaddingDp),
            dpToPx(context, params.verticalPaddingDp),
            dpToPx(context, params.horizontalPaddingDp),
            dpToPx(context, params.verticalPaddingDp),
        )
        setInt(R.id.wondaywall_widget_news_row_root, "setMinimumHeight", dpToPx(context, params.minHeightDp))
        setTextViewText(R.id.wondaywall_widget_news_title, item.title)
        setTextViewText(R.id.wondaywall_widget_news_date, formatNewsPublishedAt(item))
        setTextColor(R.id.wondaywall_widget_news_title, themedNewsPrimaryTextColor(context))
        setTextColor(R.id.wondaywall_widget_news_date, themedNewsSecondaryTextColor(context))
        setTextViewTextSize(R.id.wondaywall_widget_news_title, TypedValue.COMPLEX_UNIT_SP, NEWS_TITLE_TEXT_SIZE_SP)
        setTextViewTextSize(R.id.wondaywall_widget_news_date, TypedValue.COMPLEX_UNIT_SP, NEWS_DATE_TEXT_SIZE_SP)
        setInt(R.id.wondaywall_widget_news_title, "setMaxLines", 2)
        setInt(
            R.id.wondaywall_widget_favicon_frame,
            "setBackgroundResource",
            R.drawable.wondaywall_widget_favicon_surface
        )
        if (favicon != null) {
            setImageViewBitmap(R.id.wondaywall_widget_news_favicon, favicon)
        }
        newsUri(item.url)?.let { uri ->
            setOnClickPendingIntent(
                R.id.wondaywall_widget_news_row_root,
                PendingIntent.getActivity(
                    context,
                    pendingIntentRequestCode(10_000, item.id),
                    articleIntent(uri),
                    immutablePendingIntentFlags(),
                )
            )
        }
    }

private fun calendarRow(
    context: Context,
    item: CalendarEventItem,
    compact: Boolean,
): RemoteViews =
    RemoteViews(context.packageName, R.layout.wondaywall_widget_calendar_row).apply {
        val params = calendarRowLayoutParams(compact)
        setViewPadding(
            R.id.wondaywall_widget_calendar_row_root,
            dpToPx(context, params.horizontalPaddingDp),
            dpToPx(context, params.verticalPaddingDp),
            dpToPx(context, params.horizontalPaddingDp),
            dpToPx(context, params.verticalPaddingDp),
        )
        setInt(R.id.wondaywall_widget_calendar_row_root, "setMinimumHeight", dpToPx(context, params.minHeightDp))
        setTextViewText(R.id.wondaywall_widget_calendar_title, item.title)
        setTextViewText(R.id.wondaywall_widget_calendar_subtitle, calendarSubtitle(item))
        setTextColor(R.id.wondaywall_widget_calendar_title, themedNewsPrimaryTextColor(context))
        setTextColor(R.id.wondaywall_widget_calendar_subtitle, themedNewsSecondaryTextColor(context))
        setTextViewTextSize(R.id.wondaywall_widget_calendar_title, TypedValue.COMPLEX_UNIT_SP, CALENDAR_TITLE_TEXT_SIZE_SP)
        setTextViewTextSize(R.id.wondaywall_widget_calendar_subtitle, TypedValue.COMPLEX_UNIT_SP, CALENDAR_SUBTITLE_TEXT_SIZE_SP)
    }

private fun moreRow(
    context: Context,
    compact: Boolean,
): RemoteViews =
    RemoteViews(context.packageName, R.layout.wondaywall_widget_more_row).apply {
        val params = moreRowLayoutParams(compact)
        setViewPadding(
            R.id.wondaywall_widget_more_row_root,
            dpToPx(context, params.horizontalPaddingDp),
            dpToPx(context, params.verticalPaddingDp),
            dpToPx(context, params.horizontalPaddingDp),
            dpToPx(context, params.verticalPaddingDp),
        )
        setInt(R.id.wondaywall_widget_more_row_root, "setMinimumHeight", dpToPx(context, params.minHeightDp))
        setTextColor(R.id.wondaywall_widget_more_text, themedNewsPrimaryTextColor(context))
        setTextColor(R.id.wondaywall_widget_more_arrow, themedNewsSecondaryTextColor(context))
        setTextViewTextSize(R.id.wondaywall_widget_more_text, TypedValue.COMPLEX_UNIT_SP, MORE_TEXT_TEXT_SIZE_SP)
        setTextViewTextSize(R.id.wondaywall_widget_more_arrow, TypedValue.COMPLEX_UNIT_SP, MORE_ARROW_TEXT_SIZE_SP)
        setOnClickPendingIntent(
            R.id.wondaywall_widget_more_row_root,
            PendingIntent.getActivity(
                context,
                20_000,
                newsHomeIntent(context),
                immutablePendingIntentFlags(),
            )
        )
    }

private fun addInfoDivider(context: Context, parent: RemoteViews) {
    val divider = RemoteViews(context.packageName, R.layout.wondaywall_widget_info_divider).apply {
        setInt(R.id.wondaywall_widget_info_divider_line, "setBackgroundColor", themedDividerColor(context))
    }
    parent.addView(R.id.wondaywall_widget_info_list_container, divider)
}

private fun immutablePendingIntentFlags(): Int {
    var flags = PendingIntent.FLAG_UPDATE_CURRENT
    flags = flags or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_IMMUTABLE
    } else {
        0
    }
    return flags
}

private fun pendingIntentRequestCode(base: Int, key: String): Int =
    base + (key.hashCode() and 0x0FFFFFFF)

private fun isNightMode(context: Context): Boolean =
    (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
        Configuration.UI_MODE_NIGHT_YES

private fun themedNewsPrimaryTextColor(context: Context): Int =
    if (isNightMode(context)) {
        0xFFF8F9FA.toInt()
    } else {
        0xFF1B1B1F.toInt()
    }

private fun themedNewsSecondaryTextColor(context: Context): Int =
    if (isNightMode(context)) {
        0xDDE4E7EC.toInt()
    } else {
        0xFF535F70.toInt()
    }

private fun themedDividerColor(context: Context): Int =
    if (isNightMode(context)) {
        0x33FFFFFF
    } else {
        0x33000000
    }

private fun dpToPx(context: Context, dp: Int): Int =
    TypedValue.applyDimension(
        TypedValue.COMPLEX_UNIT_DIP,
        dp.toFloat(),
        context.resources.displayMetrics,
    ).toInt()

private fun statusText(state: WidgetDisplayState): String =
    when (state.status) {
        WidgetSlotStatus.Unconfigured -> "初期設定が必要です"
        WidgetSlotStatus.Pending -> ""
        WidgetSlotStatus.Processed -> "WondayWall"
        WidgetSlotStatus.Generating -> "生成中"
    }

private fun calendarSubtitle(item: CalendarEventItem): String {
    val timeText = calendarTimeText(item)
    val location = item.location?.takeIf { it.isNotBlank() }
    return if (location == null) {
        timeText
    } else {
        "$timeText ・$location"
    }
}

private fun calendarTimeText(item: CalendarEventItem): String {
    if (item.isAllDay) {
        return "終日"
    }

    val start = Date(item.startTime.toEpochMilliseconds())
    val end = item.endTime?.let { Date(it.toEpochMilliseconds()) }
    val dateTimeFormatter = SimpleDateFormat("M/d HH:mm", Locale.JAPAN)
    val startText = dateTimeFormatter.format(start)
    if (end == null) {
        return startText
    }

    return if (isSameDay(start, end)) {
        val timeFormatter = SimpleDateFormat("HH:mm", Locale.JAPAN)
        "$startText - ${timeFormatter.format(end)}"
    } else {
        "$startText - ${dateTimeFormatter.format(end)}"
    }
}

private fun isSameDay(left: Date, right: Date): Boolean {
    val calendar = Calendar.getInstance(Locale.JAPAN)
    calendar.time = left
    val leftYear = calendar.get(Calendar.YEAR)
    val leftDay = calendar.get(Calendar.DAY_OF_YEAR)
    calendar.time = right
    return leftYear == calendar.get(Calendar.YEAR) &&
        leftDay == calendar.get(Calendar.DAY_OF_YEAR)
}

private fun formatNewsPublishedAt(item: NewsTopicItem): String {
    val formatter = SimpleDateFormat("M/d HH:mm", Locale.JAPAN)
    return formatter.format(Date(item.publishedAt.toEpochMilliseconds()))
}

private fun generateIntent(context: Context, slotStartedAtMillis: Long): Intent =
    Intent(context, MainActivity::class.java).apply {
        action = WidgetLaunchContract.ACTION_WIDGET_OPEN
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(WidgetLaunchContract.EXTRA_SOURCE, WidgetLaunchContract.SOURCE_WIDGET)
        putExtra(
            WidgetLaunchContract.EXTRA_DESTINATION,
            WidgetLaunchContract.DESTINATION_GENERATE_CONFIRMATION
        )
        putExtra(WidgetLaunchContract.EXTRA_SLOT_STARTED_AT_MILLIS, slotStartedAtMillis)
    }

private fun newsHomeIntent(context: Context): Intent =
    Intent(context, MainActivity::class.java).apply {
        action = WidgetLaunchContract.ACTION_WIDGET_OPEN
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP
        putExtra(WidgetLaunchContract.EXTRA_SOURCE, WidgetLaunchContract.SOURCE_WIDGET)
        putExtra(WidgetLaunchContract.EXTRA_DESTINATION, WidgetLaunchContract.DESTINATION_NEWS)
    }

private fun articleIntent(uri: Uri): Intent =
    Intent(Intent.ACTION_VIEW, uri).apply {
        addCategory(Intent.CATEGORY_BROWSABLE)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK
    }

private fun newsUri(url: String?): Uri? {
    if (url.isNullOrBlank()) return null
    val uri = runCatching { Uri.parse(url) }.getOrNull() ?: return null
    val scheme = uri.scheme?.lowercase(Locale.US)
    if (scheme != "http" && scheme != "https") return null
    return uri
}
