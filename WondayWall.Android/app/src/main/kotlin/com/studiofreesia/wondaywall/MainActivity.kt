package com.studiofreesia.wondaywall

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.studiofreesia.wondaywall.ui.navigation.AppNavigation
import com.studiofreesia.wondaywall.ui.theme.WondayWallTheme

// アプリのメインアクティビティ
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            WondayWallTheme {
                val app = application as App
                AppNavigation(
                    appConfigService = app.appConfigService,
                    generationCoordinator = app.generationCoordinator,
                    historyService = app.historyService,
                    wallpaperService = app.wallpaperService,
                    contextService = app.contextService,
                    taskSchedulerService = app.taskSchedulerService,
                )
            }
        }
    }
}
