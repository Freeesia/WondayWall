package com.studiofreesia.wondaywall.services

import android.content.Context
import android.os.PowerManager
import android.util.Log
import com.studiofreesia.wondaywall.models.CalendarEventItem
import com.studiofreesia.wondaywall.models.ContextBuildResult
import com.studiofreesia.wondaywall.models.GenerationPhase
import com.studiofreesia.wondaywall.models.GenerationProgress
import com.studiofreesia.wondaywall.models.GenerationStatus
import com.studiofreesia.wondaywall.models.GenerationTrigger
import com.studiofreesia.wondaywall.models.GoogleAiServiceTier
import com.studiofreesia.wondaywall.models.HistoryItem
import com.studiofreesia.wondaywall.models.NewsTopicItem
import com.studiofreesia.wondaywall.models.PromptGenerationResult
import com.studiofreesia.wondaywall.models.PromptNewsTopic
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlin.time.Clock

// 生成処理全体を統括するコーディネーター
// UI と WorkManager の両方から呼ばれる中心クラス
class GenerationCoordinator(
    private val context: Context,
    private val appConfigService: AppConfigService,
    private val contextService: ContextService,
    private val googleAiService: GoogleAiServiceProtocol,
    private val wallpaperService: WallpaperService,
    private val historyService: HistoryService,
    private val taskSchedulerService: TaskSchedulerService,
    private val notificationHelper: NotificationHelper,
) {
    // 多重実行防止用 Mutex。待機はせず、取得できない場合は生成要求を拒否する。
    private val mutex = Mutex()

    private val _isGenerating = MutableStateFlow(false)
    val isGenerating: StateFlow<Boolean> = _isGenerating.asStateFlow()

    private val _progress = MutableStateFlow<GenerationProgress?>(null)
    val progress: StateFlow<GenerationProgress?> = _progress.asStateFlow()

    // 手動生成（後方互換用）。新規 UI からは WorkManager 経由で呼ぶ。
    suspend fun runAsync(): HistoryItem = runForWorker(GenerationTrigger.Manual)

    // スケジュール生成（後方互換用）。Worker からは runForWorker を呼ぶ。
    suspend fun runScheduledAsync(): HistoryItem = runForWorker(GenerationTrigger.Scheduled)

    // WorkManager Worker から呼ばれる生成入口
    suspend fun runForWorker(trigger: GenerationTrigger): HistoryItem {
        val config = appConfigService.getConfig()
        val serviceTier = when (trigger) {
            GenerationTrigger.Manual -> if (config.forceFlexTier) {
                GoogleAiServiceTier.Flex
            } else {
                GoogleAiServiceTier.Standard
            }
            GenerationTrigger.Scheduled,
            GenerationTrigger.StartupRecovery,
            -> GoogleAiServiceTier.Flex
        }
        val skipIfNoChanges = trigger != GenerationTrigger.Manual &&
            config.skipGenerationWhenNoChanges
        val checkScheduledSkips = trigger != GenerationTrigger.Manual
        return runGeneration(
            trigger = trigger,
            serviceTier = serviceTier,
            skipIfNoChanges = skipIfNoChanges,
            checkScheduledSkips = checkScheduledSkips,
        )
    }

    private suspend fun runGeneration(
        trigger: GenerationTrigger,
        serviceTier: GoogleAiServiceTier,
        skipIfNoChanges: Boolean,
        checkScheduledSkips: Boolean,
    ): HistoryItem {
        if (!mutex.tryLock()) {
            val rejected = HistoryItem(
                executedAt = Clock.System.now(),
                status = GenerationStatus.Skipped,
                errorSummary = "すでに生成中のため、新しい生成要求を開始しませんでした。",
                serviceTier = serviceTier,
            )
            postProgress(
                percent = 100,
                message = "すでに生成中です",
                phase = GenerationPhase.Rejected,
                historyId = rejected.id,
                trigger = trigger,
            )
            return rejected
        }

        _isGenerating.value = true
        try {
            return withGenerationWakeLock {
                runCore(
                    trigger = trigger,
                    serviceTier = serviceTier,
                    skipIfNoChanges = skipIfNoChanges,
                    checkScheduledSkips = checkScheduledSkips,
                )
            }
        } finally {
            _isGenerating.value = false
            _progress.value = null
            mutex.unlock()
        }
    }

    // 生成処理の本体
    private suspend fun runCore(
        trigger: GenerationTrigger,
        serviceTier: GoogleAiServiceTier,
        skipIfNoChanges: Boolean,
        checkScheduledSkips: Boolean,
    ): HistoryItem {
        val config = appConfigService.getConfig()
        var usedEvents: List<CalendarEventItem>? = null
        var usedNews: List<NewsTopicItem>? = null
        var generatedPrompt: String? = null
        var appliedImagePath: String? = null

        val resumable = historyService.getGeneratingWithPrompt()
        val pending = if (resumable == null) {
            historyService.getPendingGeneratingItem()
        } else {
            null
        }
        val generatingItem = when {
            resumable != null -> resumable.copy(serviceTier = serviceTier)
            pending != null -> pending.copy(
                executedAt = Clock.System.now(),
                status = GenerationStatus.Generating,
                errorSummary = null,
                appliedImagePath = null,
                serviceTier = serviceTier,
                generatedPrompt = null,
            ).also { historyService.updateHistoryItem(it) }
            else -> HistoryItem(
                executedAt = Clock.System.now(),
                status = GenerationStatus.Generating,
                serviceTier = serviceTier,
                usedPrompt = config.userPrompt.takeIf { it.isNotEmpty() },
            ).also { historyService.addHistoryItem(it) }
        }

        val isResume = resumable != null
        val isInterruptedRetry = resumable != null || pending != null
        postProgress(1, if (isResume) "処理を再開中" else "処理を開始", GenerationPhase.Starting, generatingItem.id, trigger)

        return try {
            if (checkScheduledSkips && !isInterruptedRetry) {
                val skipReason = checkPreContextSkipReason()
                if (skipReason != null) {
                    return completeSkipped(generatingItem, skipReason, trigger)
                }
            }

            postProgress(20, "生成材料を確認中", GenerationPhase.BuildingContext, generatingItem.id, trigger)
            val contextResult = contextService.buildPromptContext()
            usedEvents = contextResult.calendarEvents

            if (!isInterruptedRetry &&
                skipIfNoChanges &&
                contextResult.calendarEvents.isEmpty() &&
                !hasNewsChanged(contextResult.newsTopics)
            ) {
                usedNews = contextResult.newsTopics
                return completeSkipped(generatingItem, "生成材料に変化がないためスキップしました。", trigger, contextResult)
            }

            val promptResult: PromptGenerationResult
            if (resumable?.generatedPrompt != null) {
                generatedPrompt = resumable.generatedPrompt
                usedEvents = resumable.usedCalendarEvents ?: contextResult.calendarEvents
                usedNews = resumable.usedNewsTopics
                promptResult = PromptGenerationResult(
                    imagePrompt = resumable.generatedPrompt,
                    selectedNewsIds = resumable.usedNewsTopics?.map { it.id }.orEmpty(),
                )
            } else {
                promptResult = googleAiService.generatePrompt(
                    context = contextResult.promptContext,
                    serviceTier = serviceTier,
                    onProgress = { progress, message ->
                        postProgress(
                            percent = 35 + (progress * 30).toInt(),
                            message = message,
                            phase = GenerationPhase.GeneratingPrompt,
                            historyId = generatingItem.id,
                            trigger = trigger,
                        )
                    },
                )
                generatedPrompt = promptResult.imagePrompt
                usedNews = contextResult.newsTopics.filter {
                    promptResult.selectedNewsIds.contains(it.id)
                }
                historyService.updateHistoryItem(
                    generatingItem.copy(
                        status = GenerationStatus.GeneratingPromptReady,
                        usedCalendarEvents = contextResult.calendarEvents,
                        usedNewsTopics = usedNews,
                        usedPrompt = config.userPrompt.takeIf { it.isNotEmpty() },
                        generatedPrompt = promptResult.imagePrompt,
                    )
                )
            }

            val adoptedNews = usedNews.orEmpty()
            postProgress(65, "採用ニュース画像を取得中", GenerationPhase.FetchingOgp, generatingItem.id, trigger)
            val contextForImage = if (isResume) {
                contextResult.promptContext.copy(newsTopics = adoptedNews.map { it.toPromptNewsTopic() })
            } else {
                contextResult.promptContext
            }
            val contextWithOgp = googleAiService.fetchOgpImages(
                context = contextForImage,
                selectedNewsIds = promptResult.selectedNewsIds,
            )

            historyService.updateHistoryItem(
                generatingItem.copy(
                    status = GenerationStatus.GeneratingImageRequested,
                    usedCalendarEvents = usedEvents,
                    usedNewsTopics = adoptedNews,
                    usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                    generatedPrompt = promptResult.imagePrompt,
                )
            )

            val imageResult = googleAiService.generateImageFromPrompt(
                imagePrompt = promptResult.imagePrompt,
                context = contextWithOgp,
                serviceTier = serviceTier,
                onProgress = { progress, message ->
                    postProgress(
                        percent = 65 + (progress * 30).toInt(),
                        message = message,
                        phase = GenerationPhase.RequestingImage,
                        historyId = generatingItem.id,
                        trigger = trigger,
                    )
                },
            )
            appliedImagePath = imageResult.filePath

            postProgress(96, "壁紙を適用中", GenerationPhase.ApplyingWallpaper, generatingItem.id, trigger)
            val applyResult = wallpaperService.applyWallpaper(
                filePath = imageResult.filePath,
                updateLockScreen = config.updateLockScreen,
            )

            if (config.saveToGallery) {
                wallpaperService.saveToGallery(imageResult.filePath)
            }

            if (applyResult.isSuccess) {
                val success = generatingItem.copy(
                    status = GenerationStatus.Success,
                    errorSummary = null,
                    appliedImagePath = imageResult.filePath,
                    usedCalendarEvents = usedEvents,
                    usedNewsTopics = adoptedNews,
                    usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                    generatedPrompt = generatedPrompt,
                )
                historyService.updateHistoryItem(success)
                if (config.showNotification) {
                    notificationHelper.showSuccessNotification()
                }
                postProgress(100, "処理完了", GenerationPhase.Completed, success.id, trigger)
                success
            } else {
                val errorSummary = "壁紙の適用に失敗しました: ${applyResult.exceptionOrNull()?.message ?: "不明なエラー"}"
                val failure = generatingItem.copy(
                    status = GenerationStatus.Failure,
                    errorSummary = errorSummary,
                    appliedImagePath = imageResult.filePath,
                    usedCalendarEvents = usedEvents,
                    usedNewsTopics = adoptedNews,
                    usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                    generatedPrompt = generatedPrompt,
                )
                historyService.updateHistoryItem(failure)
                if (config.showNotification) {
                    notificationHelper.showFailureNotification(errorSummary)
                }
                postProgress(100, "生成に失敗しました", GenerationPhase.Failed, failure.id, trigger)
                failure
            }
        } catch (e: Exception) {
            Log.e(TAG, "生成に失敗しました", e)
            val failure = generatingItem.copy(
                status = GenerationStatus.Failure,
                errorSummary = e.message ?: "不明なエラー",
                appliedImagePath = appliedImagePath,
                usedCalendarEvents = usedEvents,
                usedNewsTopics = usedNews,
                usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                generatedPrompt = generatedPrompt,
            )
            historyService.updateHistoryItem(failure)
            if (config.showNotification) {
                notificationHelper.showFailureNotification(failure.errorSummary ?: "不明なエラー")
            }
            postProgress(100, "生成に失敗しました", GenerationPhase.Failed, failure.id, trigger)
            failure
        }
    }

    private suspend fun completeSkipped(
        generatingItem: HistoryItem,
        reason: String,
        trigger: GenerationTrigger,
        contextResult: ContextBuildResult? = null,
    ): HistoryItem {
        val skipped = generatingItem.copy(
            status = GenerationStatus.Skipped,
            errorSummary = reason,
            usedCalendarEvents = contextResult?.calendarEvents,
            usedNewsTopics = contextResult?.newsTopics,
        )
        historyService.updateHistoryItem(skipped)
        postProgress(100, "生成をスキップしました", GenerationPhase.Skipped, skipped.id, trigger)
        return skipped
    }

    private fun postProgress(
        percent: Int,
        message: String,
        phase: GenerationPhase,
        historyId: String?,
        trigger: GenerationTrigger,
    ) {
        _progress.value = GenerationProgress(
            percent = percent.coerceIn(0, 100),
            message = message,
            phase = phase,
            historyId = historyId,
            trigger = trigger,
        )
    }

    private suspend fun <T> withGenerationWakeLock(block: suspend () -> T): T {
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "$TAG:Generation",
        )
        return try {
            wakeLock.acquire(GENERATION_WAKE_LOCK_TIMEOUT_MS)
            block()
        } finally {
            if (wakeLock.isHeld) {
                wakeLock.release()
            }
        }
    }

    // スキップ理由を確認する（スキップ不要なら null を返す）
    private suspend fun checkPreContextSkipReason(): String? {
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

    private suspend fun hasNewsChanged(current: List<NewsTopicItem>): Boolean {
        val lastHistory = historyService.getLatestSuccessItem()
        val previous = lastHistory?.usedNewsTopics.orEmpty()
        if (previous.isEmpty()) return true
        val previousKeys = previous.map { it.url ?: it.title }.toSet()
        val currentKeys = current.map { it.url ?: it.title }.toSet()
        return previousKeys != currentKeys
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

    private fun NewsTopicItem.toPromptNewsTopic(): PromptNewsTopic =
        PromptNewsTopic(
            id = id,
            title = title,
            summary = summary,
            url = url,
            publishedAt = publishedAt,
            ogpImageUrl = ogpImageUrl,
        )

    companion object {
        private const val TAG = "GenerationCoordinator"
        private const val GENERATION_WAKE_LOCK_TIMEOUT_MS = 30 * 60 * 1000L
    }
}
