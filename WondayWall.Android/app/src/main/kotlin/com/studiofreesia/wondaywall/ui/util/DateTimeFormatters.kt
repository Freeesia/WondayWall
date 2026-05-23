package com.studiofreesia.wondaywall.ui.util

import com.studiofreesia.wondaywall.models.CalendarEventItem
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import kotlin.time.Instant

private val dateFormatter = SimpleDateFormat("MM/dd", Locale.JAPAN)
private val dateTimeFormatter = SimpleDateFormat("MM/dd HH:mm", Locale.JAPAN)
private val timeFormatter = SimpleDateFormat("HH:mm", Locale.JAPAN)

fun formatNewsPublishedAt(publishedAt: Instant): String =
    dateTimeFormatter.format(Date(publishedAt.toEpochMilliseconds()))

fun formatCalendarEventDateTime(event: CalendarEventItem): String {
    val start = Date(event.startTime.toEpochMilliseconds())
    val end = event.endTime?.let { Date(it.toEpochMilliseconds()) }

    if (event.isAllDay) {
        return "${dateFormatter.format(start)} 終日"
    }

    if (end == null) {
        return dateTimeFormatter.format(start)
    }

    return if (isSameDay(start, end)) {
        "${dateTimeFormatter.format(start)}-${timeFormatter.format(end)}"
    } else {
        "${dateTimeFormatter.format(start)} - ${dateTimeFormatter.format(end)}"
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
