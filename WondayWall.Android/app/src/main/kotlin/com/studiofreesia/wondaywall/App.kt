package com.studiofreesia.wondaywall

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import com.google.crypto.tink.aead.AeadConfig
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.ContextService
import com.studiofreesia.wondaywall.services.AiService
import com.studiofreesia.wondaywall.services.DummyAiService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.GoogleAiService
import com.studiofreesia.wondaywall.services.HistoryService
import com.studiofreesia.wondaywall.services.NotificationHelper
import com.studiofreesia.wondaywall.services.TaskSchedulerService
import com.studiofreesia.wondaywall.services.WallpaperService
import kotlinx.coroutines.runBlocking

// アプリケーションクラス：手動 DI でサービスを初期化する
class App : Application() {

    lateinit var appConfigService: AppConfigService
        private set
    lateinit var contextService: ContextService
        private set
    lateinit var aiService: AiService
        private set
    lateinit var wallpaperService: WallpaperService
        private set
    lateinit var historyService: HistoryService
        private set
    lateinit var generationCoordinator: GenerationCoordinator
        private set
    lateinit var taskSchedulerService: TaskSchedulerService
        private set
    lateinit var notificationHelper: NotificationHelper
        private set

    override fun onCreate() {
        super.onCreate()
        // Tink の暗号化アルゴリズムを登録する（AeadConfig.register() はアプリ起動時に1回のみ呼ぶ）
        AeadConfig.register()
        createNotificationChannels()
        initServices()
    }

    // サービスを依存関係順に初期化する
    private fun initServices() {
        appConfigService = AppConfigService(this)
        historyService = HistoryService(this)
        contextService = ContextService(this, appConfigService)
        aiService = createAiService()
        wallpaperService = WallpaperService(this)
        notificationHelper = NotificationHelper(this)
        taskSchedulerService = TaskSchedulerService(this, appConfigService, historyService)
        generationCoordinator = GenerationCoordinator(
            context = this,
            appConfigService = appConfigService,
            contextService = contextService,
            aiService = aiService,
            wallpaperService = wallpaperService,
            historyService = historyService,
            taskSchedulerService = taskSchedulerService,
            notificationHelper = notificationHelper,
        )
    }

    // Debug / Preview ビルドでは起動時設定に応じて実サービスとダミーAIサービスを切り替える
    private fun createAiService(): AiService {
        val useDummy = BuildConfig.DEBUG && runBlocking {
            appConfigService.getDebugConfig().useDummyAiService
        }
        return if (useDummy) {
            DummyAiService(appConfigService, filesDir)
        } else {
            GoogleAiService(appConfigService, filesDir)
        }
    }

    // 通知チャンネルを登録する（Android 8.0以上）
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = getSystemService(NotificationManager::class.java)

            val successChannel = NotificationChannel(
                NotificationHelper.CHANNEL_SUCCESS,
                getString(R.string.notification_channel_success_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = getString(R.string.notification_channel_success_desc)
            }

            val failureChannel = NotificationChannel(
                NotificationHelper.CHANNEL_FAILURE,
                getString(R.string.notification_channel_failure_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = getString(R.string.notification_channel_failure_desc)
            }

            val progressChannel = NotificationChannel(
                NotificationHelper.CHANNEL_PROGRESS,
                getString(R.string.notification_channel_progress_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = getString(R.string.notification_channel_progress_desc)
            }

            notificationManager.createNotificationChannels(
                listOf(successChannel, failureChannel, progressChannel)
            )
        }
    }
}
