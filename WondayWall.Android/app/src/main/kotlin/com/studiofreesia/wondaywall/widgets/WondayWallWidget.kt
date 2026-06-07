package com.studiofreesia.wondaywall.widgets

import android.content.Context
import android.content.Intent
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
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
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
import androidx.glance.layout.fillMaxHeight
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
import com.studiofreesia.wondaywall.models.NewsTopicItem

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
            when (displaySize) {
                WidgetDisplaySize.Small -> SmallWidgetContent(context, state)
                WidgetDisplaySize.Medium -> MediumWidgetContent(context, state)
                WidgetDisplaySize.Large -> LargeWidgetContent(context, state)
            }
        }
    }
}

private fun scrimColor(state: WidgetDisplayState): Color =
    if (state.status == WidgetSlotStatus.Processed) {
        Color(0x33000000)
    } else {
        Color(0x88000000)
    }

@Composable
private fun SmallWidgetContent(
    context: Context,
    state: WidgetDisplayState,
) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(12.dp),
        verticalAlignment = Alignment.Vertical.Bottom,
    ) {
        if (state.status != WidgetSlotStatus.Processed) {
            StatusLabel(state)
            if (state.canOpenGenerationConfirmation) {
                Spacer(GlanceModifier.height(8.dp))
                GenerateAction(context, state, compact = true)
            }
        }
    }
}

@Composable
private fun MediumWidgetContent(
    context: Context,
    state: WidgetDisplayState,
) {
    Row(
        modifier = GlanceModifier
            .fillMaxSize()
            .padding(14.dp),
        verticalAlignment = Alignment.Vertical.Top,
    ) {
        if (state.status != WidgetSlotStatus.Processed) {
            Column(
                modifier = GlanceModifier
                    .fillMaxHeight()
                    .width(116.dp),
            ) {
                StatusLabel(state)
                if (state.canOpenGenerationConfirmation) {
                    Spacer(GlanceModifier.height(8.dp))
                    GenerateAction(context, state, compact = false)
                }
            }
        }
        if (state.status == WidgetSlotStatus.Processed) {
            NewsList(state.usedNewsTopics.take(2))
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
        if (state.status != WidgetSlotStatus.Processed) {
            StatusLabel(state)
            if (state.canOpenGenerationConfirmation) {
                Spacer(GlanceModifier.height(8.dp))
                GenerateAction(context, state, compact = false)
            }
        }
        if (state.status == WidgetSlotStatus.Processed) {
            NewsList(state.usedNewsTopics.take(3))
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
            fontSize = 13.sp,
            textAlign = TextAlign.Center,
        ),
        modifier = GlanceModifier
            .background(ColorProvider(Color(0xFF3F51B5)))
            .cornerRadius(50.dp)
            .padding(horizontal = if (compact) 10.dp else 14.dp, vertical = 8.dp)
            .clickable(actionStartActivity(generateIntent(context, state.currentSlotStartedAtMillis))),
    )
}

@Composable
private fun NewsList(news: List<NewsTopicItem>) {
    Column(modifier = GlanceModifier.fillMaxWidth()) {
        news.forEach { item ->
            val modifier = GlanceModifier
                .fillMaxWidth()
                .padding(bottom = 6.dp)
                .background(ColorProvider(Color(0x66000000)))
                .cornerRadius(8.dp)
                .padding(horizontal = 8.dp, vertical = 6.dp)
                .let {
                    val url = item.url
                    if (url.isNullOrBlank()) {
                        it
                    } else {
                        it.clickable(actionStartActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))))
                    }
                }
            Text(
                text = item.title,
                maxLines = 2,
                style = captionStyle(),
                modifier = modifier,
            )
        }
    }
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

private fun statusText(state: WidgetDisplayState): String =
    when (state.status) {
        WidgetSlotStatus.Unconfigured -> "初期設定が必要です"
        WidgetSlotStatus.Pending -> "未実行スロット"
        WidgetSlotStatus.Processed -> "WondayWall"
        WidgetSlotStatus.Generating -> state.generationProgress?.let { "生成中 ${it.percent}%" } ?: "生成中"
    }

private fun captionStyle(): TextStyle =
    TextStyle(
        color = ColorProvider(Color.White.copy(alpha = 0.92f)),
        fontSize = 11.sp,
    )

private enum class WidgetDisplaySize {
    Small,
    Medium,
    Large,
}
