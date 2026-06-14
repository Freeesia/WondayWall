package com.studiofreesia.wondaywall.widgets

import android.content.Intent

// ウィジェットからアプリ本体へ渡す起動パラメータ
object WidgetLaunchContract {
    const val ACTION_WIDGET_OPEN = "com.studiofreesia.wondaywall.action.WIDGET_OPEN"
    const val EXTRA_SOURCE = "source"
    const val EXTRA_DESTINATION = "destination"
    const val EXTRA_SLOT_STARTED_AT_MILLIS = "slotStartedAtMillis"
    const val SOURCE_WIDGET = "widget"
    const val DESTINATION_GENERATE_CONFIRMATION = "generate-confirmation"
    const val DESTINATION_NEWS = "news"

    fun parse(intent: Intent?): WidgetLaunchRequest? {
        if (intent?.action != ACTION_WIDGET_OPEN) return null
        if (intent.getStringExtra(EXTRA_SOURCE) != SOURCE_WIDGET) return null
        val destination = intent.getStringExtra(EXTRA_DESTINATION) ?: return null
        return when (destination) {
            DESTINATION_GENERATE_CONFIRMATION -> {
                val slotStartedAtMillis = intent.getLongExtra(EXTRA_SLOT_STARTED_AT_MILLIS, -1L)
                if (slotStartedAtMillis <= 0L) return null
                WidgetLaunchRequest(destination, slotStartedAtMillis)
            }
            DESTINATION_NEWS -> WidgetLaunchRequest(destination, null)
            else -> null
        }
    }
}

data class WidgetLaunchRequest(
    val destination: String,
    val slotStartedAtMillis: Long?,
)
