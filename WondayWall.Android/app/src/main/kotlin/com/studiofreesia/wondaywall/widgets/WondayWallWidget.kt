package com.studiofreesia.wondaywall.widgets

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
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
import com.studiofreesia.wondaywall.MainActivity
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
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
        val state = WidgetStateRepository(context).load()
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

@Composable
private fun InfoContent(
    context: Context,
    state: WidgetDisplayState,
    compact: Boolean,
) {
    val page = selectedInfoPage(context, state)
    val limit = infoLimit(page, compact, shouldShowInfoPager(state))

    Column(modifier = GlanceModifier.fillMaxWidth()) {
        if (shouldShowInfoPager(state)) {
            InfoPager(selected = page, compact = compact)
            Spacer(GlanceModifier.height(if (compact) 7.dp else 10.dp))
        }

        when (page) {
            WidgetInfoPage.Calendar -> CalendarList(state.usedCalendarEvents.take(limit), compact)
            WidgetInfoPage.News -> NewsList(state.usedNewsTopics.take(limit), state.faviconImages, compact)
        }
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

@Composable
private fun CalendarList(
    events: List<CalendarEventItem>,
    compact: Boolean,
) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        events.forEach { item ->
            CalendarRow(item, compact)
            Spacer(GlanceModifier.height(if (compact) 6.dp else 8.dp))
        }
    }
}

@Composable
private fun CalendarRow(
    item: CalendarEventItem,
    compact: Boolean,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .background(ColorProvider(Color(0x77000000)))
            .cornerRadius(10.dp)
            .padding(horizontal = if (compact) 10.dp else 12.dp, vertical = if (compact) 8.dp else 10.dp),
    ) {
        Text(
            text = item.title,
            maxLines = 1,
            style = TextStyle(
                color = ColorProvider(Color.White),
                fontWeight = FontWeight.Bold,
                fontSize = if (compact) 14.sp else 20.sp,
            ),
        )
        Spacer(GlanceModifier.height(2.dp))
        Text(
            text = calendarSubtitle(item),
            maxLines = 1,
            style = TextStyle(
                color = ColorProvider(Color.White.copy(alpha = 0.86f)),
                fontWeight = FontWeight.Medium,
                fontSize = if (compact) 11.sp else 14.sp,
            ),
        )
    }
}

@Composable
private fun NewsList(
    news: List<NewsTopicItem>,
    faviconImages: Map<String, Bitmap>,
    compact: Boolean,
) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        news.forEach { item ->
            val uri = newsUri(item.url)
            val modifier = GlanceModifier
                .fillMaxWidth()
                .background(ColorProvider(Color(0x66000000)))
                .cornerRadius(8.dp)
                .padding(horizontal = if (compact) 8.dp else 10.dp, vertical = if (compact) 6.dp else 8.dp)
                .let {
                    if (uri == null) {
                        it
                    } else {
                        it.clickable(actionStartActivity(articleIntent(uri)))
                    }
                }

            Row(
                modifier = modifier,
                verticalAlignment = Alignment.Vertical.Top,
            ) {
                FaviconImage(faviconImages[item.id])
                Spacer(GlanceModifier.width(8.dp))
                Column(modifier = GlanceModifier.fillMaxWidth()) {
                    Text(
                        text = item.title,
                        maxLines = if (compact) 1 else 2,
                        style = TextStyle(
                            color = ColorProvider(Color.White),
                            fontWeight = FontWeight.Medium,
                            fontSize = 11.sp,
                        ),
                    )
                    Spacer(GlanceModifier.height(3.dp))
                    Text(
                        text = formatNewsPublishedAt(item),
                        maxLines = 1,
                        style = TextStyle(
                            color = ColorProvider(Color.White.copy(alpha = 0.76f)),
                            fontSize = 10.sp,
                        ),
                    )
                }
            }
            Spacer(GlanceModifier.height(if (compact) 6.dp else 8.dp))
        }
    }
}

@Composable
private fun FaviconImage(bitmap: Bitmap?) {
    Box(
        modifier = GlanceModifier
            .width(16.dp)
            .height(16.dp)
            .background(ColorProvider(Color(0xAAFFFFFF)))
            .cornerRadius(4.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (bitmap != null) {
            Image(
                provider = ImageProvider(bitmap),
                contentDescription = null,
                contentScale = ContentScale.Fit,
                modifier = GlanceModifier
                    .width(16.dp)
                    .height(16.dp)
                    .padding(2.dp),
            )
        }
    }
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
        page == WidgetInfoPage.News && compact -> 3
        page == WidgetInfoPage.News -> 5
        page == WidgetInfoPage.Calendar && compact -> 2
        else -> 4
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
