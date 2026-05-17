package com.studiofreesia.wondaywall.services

import android.content.Context
import android.util.Log
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.HistoryItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.time.Clock

// 生成処理全体を統括するコーディネーター
// UI と WorkManager の両方から呼ばれる中心クラス
class GenerationCoordinator(
    private val context: Context,
    private val appConfigService: AppConfigService,
    private val contextService: ContextService,
    private val googleAiService: GoogleAiService,
    private val wallpaperService: WallpaperService,
    private val historyService: HistoryService,
    private val taskSchedulerService: TaskSchedulerService,
    private val notificationHelper: NotificationHelper,
) {
    // 多重実行防止用 Mutex
    private val mutex = Mutex()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    // 手動生成（ユーザー操作から呼ぶ）
    suspend fun runAsync(): HistoryItem {
        return mutex.withLock {
            _isGenerating.value = true
            try {
                val config = appConfigService.getConfig()
                // forceFlexTier が有効な場合は Flex ティアを使用する
                val tier = if (config.forceFlexTier) GoogleAiServiceTier.Flex else GoogleAiServiceTier.Standard
                generate(serviceTier = tier)
            } finally {
                _isGenerating.value = false
            }
        }
    }

    // スケジュール生成（WorkManager およびアプリ起動時チェックから呼ぶ）
    suspend fun runScheduledAsync(): HistoryItem {
        return mutex.withLock {
            val config = appConfigService.getConfig()

            // スキップ判定を行う
            val skipReason = checkSkipReason()
            if (skipReason != null) {
                val skippedItem = HistoryItem(
                    executedAt = Clock.System.now(),
                    isSuccess = false,
                    errorSummary = skipReason,
                    appliedImagePath = null,
                    usedCalendarEvents = null,
                    usedNewsTopics = null,
                    serviceTier = GoogleAiServiceTier.Flex,
                    isSkipped = true,
                )
                recordHistoryItem(skippedItem)
                return@withLock skippedItem
            }

            _isGenerating.value = true
            try {
                val result = generate(serviceTier = GoogleAiServiceTier.Flex)
                // 次回スロットの WorkManager を登録する
                taskSchedulerService.scheduleNext()
                result
            } finally {
                _isGenerating.value = false
            }
        }
    }

    // 生成処理の本体
    private suspend fun generate(serviceTier: GoogleAiServiceTier): HistoryItem {
        val config = appConfigService.getConfig()

        return try {
            // コンテキストを構築する
            val buildResult = contextService.buildPromptContext()

            // 画像を生成して保存する
            val imageInfo = googleAiService.generateWallpaper(
                context = buildResult.promptContext,
                serviceTier = serviceTier,
            )

            // 壁紙を適用する
            val applyResult = wallpaperService.applyWallpaper(
                filePath = imageInfo.filePath,
                updateLockScreen = config.updateLockScreen,
            )

            // ギャラリー保存設定が有効な場合は保存する
            if (config.saveToGallery) {
                wallpaperService.saveToGallery(imageInfo.filePath)
            }

            val isSuccess = applyResult.isSuccess
            val errorSummary = applyResult.exceptionOrNull()?.message

            val historyItem = HistoryItem(
                executedAt = Clock.System.now(),
                isSuccess = isSuccess,
                errorSummary = if (isSuccess) null else "壁紙の適用に失敗しました: $errorSummary",
                appliedImagePath = imageInfo.filePath,
                usedCalendarEvents = buildResult.calendarEvents,
                usedNewsTopics = buildResult.newsTopics,
                serviceTier = serviceTier,
                usedPrompt = config.userPrompt.takeIf { it.isNotEmpty() },
            )
            recordHistoryItem(historyItem)

            // 通知を送る
            if (config.showNotification) {
                if (isSuccess) {
                    notificationHelper.showSuccessNotification()
                } else {
                    notificationHelper.showFailureNotification(errorSummary ?: "不明なエラー")
                }
            }

            historyItem
        } catch (e: Exception) {
            val historyItem = HistoryItem(
                executedAt = Clock.System.now(),
                isSuccess = false,
                errorSummary = e.message ?: "不明なエラー",
                appliedImagePath = null,
                usedCalendarEvents = null,
                usedNewsTopics = null,
                serviceTier = serviceTier,
            )
            recordHistoryItem(historyItem)

            if (config.showNotification) {
                notificationHelper.showFailureNotification(historyItem.errorSummary ?: "不明なエラー")
            }
            historyItem
        }
    }

    // 生成結果を履歴に保存する。保存失敗は生成処理自体の戻り値を壊さず、ログに残す。
    private suspend fun recordHistoryItem(item: HistoryItem) {
        if (!historyService.addHistoryItem(item)) {
            Log.e(TAG, "生成履歴の保存に失敗しました")
        }
    }

    // スキップ理由を確認する（スキップ不要なら null を返す）
    private suspend fun checkSkipReason(): String? {
        val appConfig = appConfigService.getConfig()

        // スロット判定：現在スロットがすでに処理済みか確認する
        if (taskSchedulerService.isCurrentSlotProcessed()) {
            return "現在のスケジュールスロットはすでに処理済みです。"
        }

        // Wi-Fi のみ設定
        if (appConfig.generateOnlyOnWifi && !isWifiConnected()) {
            return "Wi-Fi 接続がないためスキップしました。"
        }

        // 省電力モード設定
        if (appConfig.skipOnBatterySaver && isBatterySaverActive()) {
            return "省電力モードが有効なためスキップしました。"
        }

        return null
    }

    // Wi-Fi 接続中か確認する
    private fun isWifiConnected(): Boolean {
        val connectivityManager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as android.net.ConnectivityManager
        val network = connectivityManager.activeNetwork ?: return false
        val capabilities = connectivityManager.getNetworkCapabilities(network) ?: return false
        return capabilities.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)
    }

    // 省電力モードが有効か確認する
    private fun isBatterySaverActive(): Boolean {
        val powerManager = context.getSystemService(Context.POWER_SERVICE)
            as android.os.PowerManager
        return powerManager.isPowerSaveMode
    }

    companion object {
        private const val TAG = "GenerationCoordinator"
    }
}
