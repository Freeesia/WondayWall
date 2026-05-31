package com.studiofreesia.wondaywall.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.ui.util.formatCalendarEventDateTime
import com.studiofreesia.wondaywall.ui.util.formatNewsPublishedAt

// 生成前に使用する予定とニュースを確認するための共通プレビュー
@Composable
fun GenerationContextPreview(
    events: List<CalendarEventItem>,
    news: List<NewsTopicItem>,
    isLoading: Boolean,
    modifier: Modifier = Modifier,
    showEmptySections: Boolean = false,
    eventsTitle: String = "カレンダー予定",
    newsTitle: String = "ニュース",
    emptyEventsText: String = "今回は予定を使いません",
    emptyNewsText: String = "今回はニュースを使いません",
) {
    Column(
        modifier = modifier,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (isLoading) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(120.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator()
            }
        } else {
            if (events.isNotEmpty() || showEmptySections) {
                GenerationPreviewSection(
                    title = eventsTitle,
                    emptyText = emptyEventsText,
                    isEmpty = events.isEmpty(),
                    icon = { Icon(Icons.Default.CalendarMonth, contentDescription = null) },
                ) {
                    events.forEachIndexed { index, event ->
                        if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                        CalendarEventPreviewRow(event)
                    }
                }
            }

            if (news.isNotEmpty() || showEmptySections) {
                GenerationPreviewSection(
                    title = newsTitle,
                    emptyText = emptyNewsText,
                    isEmpty = news.isEmpty(),
                    icon = { Icon(Icons.Default.Newspaper, contentDescription = null) },
                ) {
                    news.forEachIndexed { index, item ->
                        if (index > 0) HorizontalDivider(modifier = Modifier.padding(start = 12.dp))
                        NewsPreviewRow(item)
                    }
                }
            }

            if (!showEmptySections && events.isEmpty() && news.isEmpty()) {
                Text(
                    "利用できるカレンダー予定・ニュースがありません",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun GenerationPreviewSection(
    title: String,
    emptyText: String,
    isEmpty: Boolean,
    icon: @Composable () -> Unit,
    content: @Composable () -> Unit,
) {
    ElevatedCard(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                icon()
                Text(title, style = MaterialTheme.typography.titleSmall)
            }
            Spacer(Modifier.height(8.dp))
            if (isEmpty) {
                Text(
                    emptyText,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else {
                content()
            }
        }
    }
}

@Composable
private fun CalendarEventPreviewRow(event: CalendarEventItem) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
    ) {
        Text(event.title, style = MaterialTheme.typography.bodyMedium)
        Text(
            formatCalendarEventDateTime(event),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun NewsPreviewRow(item: NewsTopicItem) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FaviconIcon(url = item.url)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Text(
                text = item.title,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 2,
            )
            Text(
                text = formatNewsPublishedAt(item.publishedAt),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
