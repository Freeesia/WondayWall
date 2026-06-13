package com.studiofreesia.wondaywall.widgets

import android.content.Context
import androidx.glance.appwidget.updateAll

// アプリ側の状態変化から Glance ウィジェット更新を要求するヘルパー
object WondayWallWidgetUpdater {
    suspend fun update(context: Context) {
        WondayWallWidget().updateAll(context)
    }
}
