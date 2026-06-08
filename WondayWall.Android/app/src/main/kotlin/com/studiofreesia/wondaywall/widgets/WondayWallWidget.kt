package com.studiofreesia.wondaywall.widgets

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.Build
import android.net.Uri
import android.util.TypedValue
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.AndroidRemoteViews
import androidx.glance.appwidget.ExperimentalGlanceRemoteViewsApi
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.studiofreesia.wondaywall.R
import com.studiofreesia.wondaywall.MainActivity
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import kotlinx.coroutines.runBlocking
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

private enum class WidgetDisplaySize {
    Small,
    Medium,
    Large,
}

private enum class WidgetInfoPage {
    Calendar,
    News,
}

private const val EXTRA_STACK_PAGE = "stackPage"
private const val EXTRA_STACK_COMPACT = "stackCompact"

private object WidgetInfoPageStore {
    private const val PREFS_NAME = "wondaywall_widget"
    private const val KEY_INFO_PAGE = "infoPage"

    fun current(context: Context): WidgetInfoPage? =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_INFO_PAGE, null)
            ?.let { value -> runCatching { WidgetInfoPage.valueOf(value) }.getOrNull() }

    fun set(context: Context, page: WidgetInfoPage) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_INFO_PAGE, page.name)
            .apply()
    }
}

class SelectWidgetInfoPageAction : ActionCallback {
    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters,
    ) {
        val page = parameters[PageKey]
            ?.let { value -> runCatching { WidgetInfoPage.valueOf(value) }.getOrNull() }
            ?: return
        WidgetInfoPageStore.set(context, page)
        WondayWallWidget().update(context, glanceId)
    }

    companion object {
        val PageKey = ActionParameters.Key<String>("page")
    }
}

class WondayWallWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(
            DpSize(110.dp, 110.dp),
            DpSize(250.dp, 110.dp),
            DpSize(250.dp, 250.dp),
        )
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = WidgetStateRepository(context).load(includeFaviconImages = false)
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
                    WidgetDisplaySize.Medium -> MediumWidgetContent(context, state)
                    WidgetDisplaySize.Large -> LargeWidgetContent(context, state)
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
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(14.dp),
    ) {
        if (shouldShowStatus(state)) {
            StatusLabel(state)
            Spacer(GlanceModifier.height(8.dp))
        }
        if (shouldShowInfo(state)) {
            InfoContent(context, state, compact = true)
        }
    }
}

@Composable
private fun LargeWidgetContent(
    context: Context,
    state: WidgetDisplayState,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(16.dp),
    ) {
        if (shouldShowStatus(state)) {
            StatusLabel(state)
            Spacer(GlanceModifier.height(10.dp))
        }
        if (shouldShowInfo(state)) {
            InfoContent(context, state, compact = false)
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
) {
    val page = selectedInfoPage(context, state)

    Column(modifier = GlanceModifier.fillMaxWidth()) {
        if (shouldShowInfoPager(state)) {
            InfoPager(selected = page, compact = compact)
            Spacer(GlanceModifier.height(if (compact) 7.dp else 10.dp))
        }

        AndroidRemoteViews(
            remoteViews = stackRemoteViews(context, page, compact),
            modifier = GlanceModifier
                .fillMaxWidth()
                .height(stackHeight(page, compact)),
        )
    }
}

@Composable
private fun InfoPager(
    selected: WidgetInfoPage,
    compact: Boolean,
) {
    Row(modifier = GlanceModifier.fillMaxWidth()) {
        InfoPageButton(
            title = "予定",
            page = WidgetInfoPage.Calendar,
            selected = selected == WidgetInfoPage.Calendar,
            compact = compact,
        )
        Spacer(GlanceModifier.width(6.dp))
        InfoPageButton(
            title = "ニュース",
            page = WidgetInfoPage.News,
            selected = selected == WidgetInfoPage.News,
            compact = compact,
        )
    }
}

@Composable
private fun InfoPageButton(
    title: String,
    page: WidgetInfoPage,
    selected: Boolean,
    compact: Boolean,
) {
    Text(
        text = title,
        maxLines = 1,
        style = TextStyle(
            color = ColorProvider(if (selected) Color.Black else Color.White),
            fontWeight = FontWeight.Bold,
            fontSize = if (compact) 12.sp else 14.sp,
            textAlign = TextAlign.Center,
        ),
        modifier = GlanceModifier
            .width(if (compact) 76.dp else 96.dp)
            .background(ColorProvider(if (selected) Color(0xEEFFFFFF) else Color(0x66000000)))
            .cornerRadius(50.dp)
            .padding(horizontal = if (compact) 10.dp else 12.dp, vertical = if (compact) 5.dp else 7.dp)
            .clickable(
                actionRunCallback<SelectWidgetInfoPageAction>(
                    actionParametersOf(SelectWidgetInfoPageAction.PageKey to page.name)
                )
            ),
    )
}

private fun shouldShowStatus(state: WidgetDisplayState): Boolean =
    state.status != WidgetSlotStatus.Processed && state.status != WidgetSlotStatus.Pending

private fun shouldShowInfo(state: WidgetDisplayState): Boolean =
    state.status == WidgetSlotStatus.Processed &&
        (state.usedCalendarEvents.isNotEmpty() || state.usedNewsTopics.isNotEmpty())

private fun shouldShowInfoPager(state: WidgetDisplayState): Boolean =
    state.usedCalendarEvents.isNotEmpty() && state.usedNewsTopics.isNotEmpty()

private fun shouldShowSmallNewsButton(state: WidgetDisplayState): Boolean =
    state.status == WidgetSlotStatus.Processed

private fun selectedInfoPage(
    context: Context,
    state: WidgetDisplayState,
): WidgetInfoPage {
    val storedPage = WidgetInfoPageStore.current(context)
    if (storedPage == WidgetInfoPage.Calendar && state.usedCalendarEvents.isNotEmpty()) {
        return WidgetInfoPage.Calendar
    }
    if (storedPage == WidgetInfoPage.News && state.usedNewsTopics.isNotEmpty()) {
        return WidgetInfoPage.News
    }
    if (state.usedNewsTopics.isNotEmpty()) {
        return WidgetInfoPage.News
    }
    return WidgetInfoPage.Calendar
}

private fun infoLimit(
    page: WidgetInfoPage,
    compact: Boolean,
    showPager: Boolean,
): Int =
    when {
        page == WidgetInfoPage.News && compact && showPager -> 2
        page == WidgetInfoPage.News && compact -> 2
        page == WidgetInfoPage.News -> 5
        page == WidgetInfoPage.Calendar && compact -> 2
        else -> 4
    }

private fun stackHeight(page: WidgetInfoPage, compact: Boolean): Dp =
    when {
        page == WidgetInfoPage.News && compact -> 76.dp
        page == WidgetInfoPage.News -> 178.dp
        page == WidgetInfoPage.Calendar && compact -> 78.dp
        else -> 176.dp
    }

private fun stackRemoteViews(
    context: Context,
    page: WidgetInfoPage,
    compact: Boolean,
): RemoteViews =
    RemoteViews(context.packageName, R.layout.wondaywall_widget_stack).apply {
        val adapterIntent = Intent(context, WondayWallWidgetStackService::class.java).apply {
            putExtra(EXTRA_STACK_PAGE, page.name)
            putExtra(EXTRA_STACK_COMPACT, compact)
            data = Uri.parse("wondaywall://widget-stack/${page.name}/$compact/${System.currentTimeMillis()}")
        }
        setRemoteAdapter(R.id.wondaywall_widget_stack_view, adapterIntent)
        setPendingIntentTemplate(
            R.id.wondaywall_widget_stack_view,
            PendingIntent.getActivity(
                context,
                0,
                Intent(Intent.ACTION_VIEW).addCategory(Intent.CATEGORY_BROWSABLE),
                widgetPendingIntentTemplateFlags()
            )
        )
    }

class WondayWallWidgetStackService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsService.RemoteViewsFactory =
        WondayWallWidgetStackFactory(applicationContext, intent)
}

private class WondayWallWidgetStackFactory(
    private val context: Context,
    intent: Intent,
) : RemoteViewsService.RemoteViewsFactory {
    private val page = intent.getStringExtra(EXTRA_STACK_PAGE)
        ?.let { value -> runCatching { WidgetInfoPage.valueOf(value) }.getOrNull() }
        ?: WidgetInfoPage.News
    private val compact = intent.getBooleanExtra(EXTRA_STACK_COMPACT, false)
    private var pages: List<WidgetStackPage> = emptyList()

    override fun onCreate() = Unit

    override fun onDataSetChanged() {
        val state = runBlocking { WidgetStateRepository(context).load() }
        val showPager = state.usedCalendarEvents.isNotEmpty() && state.usedNewsTopics.isNotEmpty()
        val limit = infoLimit(page, compact, showPager)
        pages = when (page) {
            WidgetInfoPage.Calendar -> state.usedCalendarEvents
                .chunked(limit)
                .map { WidgetStackPage.Calendar(it) }
            WidgetInfoPage.News -> state.usedNewsTopics
                .chunked(limit)
                .map { WidgetStackPage.News(it, state.faviconImages) }
        }
    }

    override fun onDestroy() {
        pages = emptyList()
    }

    override fun getCount(): Int = pages.size

    override fun getViewAt(position: Int): RemoteViews {
        val page = pages.getOrNull(position)
            ?: return RemoteViews(context.packageName, R.layout.wondaywall_widget_stack_page)
        return when (page) {
            is WidgetStackPage.Calendar -> calendarPage(page.events)
            is WidgetStackPage.News -> newsPage(page.news, page.faviconImages)
        }
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false

    private fun newsPage(
        news: List<NewsTopicItem>,
        faviconImages: Map<String, Bitmap>,
    ): RemoteViews =
        RemoteViews(context.packageName, R.layout.wondaywall_widget_stack_page).apply {
            setInt(
                R.id.wondaywall_widget_stack_page_root,
                "setBackgroundResource",
                R.drawable.wondaywall_widget_news_surface
            )
            removeAllViews(R.id.wondaywall_widget_stack_page_container)
            news.forEachIndexed { index, item ->
                if (index > 0) {
                    addDivider(this)
                }
                addView(R.id.wondaywall_widget_stack_page_container, newsRow(item, faviconImages[item.id]))
            }
        }

    private fun calendarPage(events: List<CalendarEventItem>): RemoteViews =
        RemoteViews(context.packageName, R.layout.wondaywall_widget_stack_page).apply {
            setInt(R.id.wondaywall_widget_stack_page_root, "setBackgroundColor", 0x00000000)
            removeAllViews(R.id.wondaywall_widget_stack_page_container)
            events.forEachIndexed { index, item ->
                if (index > 0) {
                    addView(
                        R.id.wondaywall_widget_stack_page_container,
                        RemoteViews(context.packageName, R.layout.wondaywall_widget_stack_spacer)
                    )
                }
                addView(R.id.wondaywall_widget_stack_page_container, calendarRow(item))
            }
        }

    private fun newsRow(item: NewsTopicItem, favicon: Bitmap?): RemoteViews =
        RemoteViews(context.packageName, R.layout.wondaywall_widget_news_row).apply {
            setTextViewText(R.id.wondaywall_widget_news_title, item.title)
            setTextViewText(R.id.wondaywall_widget_news_date, formatNewsPublishedAt(item))
            setTextColor(R.id.wondaywall_widget_news_title, themedNewsPrimaryTextColor(context))
            setTextColor(R.id.wondaywall_widget_news_date, themedNewsSecondaryTextColor(context))
            setTextViewTextSize(R.id.wondaywall_widget_news_title, TypedValue.COMPLEX_UNIT_SP, if (compact) 11f else 12f)
            setInt(
                R.id.wondaywall_widget_favicon_frame,
                "setBackgroundResource",
                R.drawable.wondaywall_widget_favicon_surface
            )
            if (favicon != null) {
                setImageViewBitmap(R.id.wondaywall_widget_news_favicon, favicon)
            }
            newsUri(item.url)?.let { uri ->
                setOnClickFillInIntent(R.id.wondaywall_widget_news_row_root, articleIntent(uri))
            }
        }

    private fun calendarRow(item: CalendarEventItem): RemoteViews =
        RemoteViews(context.packageName, R.layout.wondaywall_widget_calendar_row).apply {
            setInt(
                R.id.wondaywall_widget_calendar_row_root,
                "setBackgroundResource",
                R.drawable.wondaywall_widget_info_row_surface
            )
            setTextViewText(R.id.wondaywall_widget_calendar_title, item.title)
            setTextViewText(R.id.wondaywall_widget_calendar_subtitle, calendarSubtitle(item))
            setTextColor(R.id.wondaywall_widget_calendar_title, themedNewsPrimaryTextColor(context))
            setTextColor(R.id.wondaywall_widget_calendar_subtitle, themedNewsSecondaryTextColor(context))
        }

    private fun addDivider(parent: RemoteViews) {
        val divider = RemoteViews(context.packageName, R.layout.wondaywall_widget_stack_divider).apply {
            setInt(R.id.wondaywall_widget_stack_divider_line, "setBackgroundColor", themedDividerColor(context))
        }
        parent.addView(R.id.wondaywall_widget_stack_page_container, divider)
    }
}

private sealed class WidgetStackPage {
    data class Calendar(val events: List<CalendarEventItem>) : WidgetStackPage()
    data class News(
        val news: List<NewsTopicItem>,
        val faviconImages: Map<String, Bitmap>,
    ) : WidgetStackPage()
}

private fun widgetPendingIntentTemplateFlags(): Int {
    var flags = PendingIntent.FLAG_UPDATE_CURRENT
    flags = flags or if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        PendingIntent.FLAG_MUTABLE
    } else {
        0
    }
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        flags = flags or PendingIntent.FLAG_ALLOW_UNSAFE_IMPLICIT_INTENT
    }
    return flags
}

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
