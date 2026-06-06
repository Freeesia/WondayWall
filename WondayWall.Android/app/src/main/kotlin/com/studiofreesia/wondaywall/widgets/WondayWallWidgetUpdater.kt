package com.studiofreesia.wondaywall.widgets

import android.content.Context
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

// アプリ側の状態変化から Glance ウィジェット更新を要求するヘルパー
object WondayWallWidgetUpdater {
    fun requestUpdate(context: Context) {
        CoroutineScope(Dispatchers.Default).launch {
            update(context)
        }
    }

    suspend fun update(context: Context) {
        WondayWallWidget().updateAll(context)
    }
}
