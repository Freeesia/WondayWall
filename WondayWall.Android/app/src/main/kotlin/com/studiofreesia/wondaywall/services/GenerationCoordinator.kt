package com.studiofreesia.wondaywall.services

import android.content.Context
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
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import java.io.File
import java.io.IOException
import kotlin.math.roundToInt
import kotlin.time.Clock

// 生成処理全体を統括するコーディネーター
// UI と WorkManager の両方から呼ばれる中心クラス
class GenerationCoordinator(
    private val context: Context,
    private val appConfigService: AppConfigService,
    private val contextService: ContextService,
    private val aiService: AiService,
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
            return runCore(
                trigger = trigger,
                serviceTier = serviceTier,
                skipIfNoChanges = skipIfNoChanges,
                checkScheduledSkips = checkScheduledSkips,
            )
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
        var appliedImageUri: String? = null
        var temporaryImagePath: String? = null

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
                appliedImageUri = null,
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

            postProgress(5, "生成材料を確認中", GenerationPhase.BuildingContext, generatingItem.id, trigger)
            val contextResult = contextService.buildPromptContext { progress, message ->
                postProgress(
                    percent = (progress * 100).roundToInt(),
                    message = message,
                    phase = GenerationPhase.BuildingContext,
                    historyId = generatingItem.id,
                    trigger = trigger,
                )
            }
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
                promptResult = aiService.generatePrompt(
                    context = contextResult.promptContext,
                    serviceTier = serviceTier,
                    onProgress = { progress, message ->
                        postProgress(
                            percent = 15 + (progress * 30).roundToInt(),
                            message = message,
                            phase = GenerationPhase.GeneratingPrompt,
                            historyId = generatingItem.id,
                            trigger = trigger,
                        )
                    },
                )
                generatedPrompt = promptResult.imagePrompt
                usedNews = promptResult.usedNewsTopics
                    ?: contextResult.newsTopics.filter {
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
            val contextForImage = if (isResume) {
                contextResult.promptContext.copy(newsTopics = adoptedNews.map { it.toPromptNewsTopic() })
            } else {
                contextResult.promptContext
            }
            val contextWithOgp = runWithSyntheticProgress(
                startPercent = 45,
                maxBeforeCompletionPercent = 50,
                message = "採用ニュース画像を取得中",
                phase = GenerationPhase.FetchingOgp,
                historyId = generatingItem.id,
                trigger = trigger,
            ) {
                aiService.fetchOgpImages(
                    context = contextForImage,
                    selectedNewsIds = promptResult.selectedNewsIds,
                )
            }
            postProgress(50, "採用ニュース画像の取得完了", GenerationPhase.FetchingOgp, generatingItem.id, trigger)

            historyService.updateHistoryItem(
                generatingItem.copy(
                    status = GenerationStatus.GeneratingImageRequested,
                    usedCalendarEvents = usedEvents,
                    usedNewsTopics = adoptedNews,
                    usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                    generatedPrompt = promptResult.imagePrompt,
                )
            )

            val imageResult = aiService.generateImageFromPrompt(
                imagePrompt = promptResult.imagePrompt,
                context = contextWithOgp,
                serviceTier = serviceTier,
                onProgress = { progress, message ->
                    postProgress(
                        percent = 50 + (progress * 45).roundToInt(),
                        message = message,
                        phase = GenerationPhase.RequestingImage,
                        historyId = generatingItem.id,
                        trigger = trigger,
                    )
                },
            )

            temporaryImagePath = imageResult.temporaryFilePath
            postProgress(95, "写真に保存中", GenerationPhase.ApplyingWallpaper, generatingItem.id, trigger)
            val imageUri = wallpaperService.saveToPhotos(imageResult.temporaryFilePath)
                .getOrElse { error ->
                    throw IOException("写真領域への保存に失敗しました: ${error.message ?: "不明なエラー"}", error)
                }
            val imageUriString = imageUri.toString()
            appliedImageUri = imageUriString

            postProgress(96, "壁紙を適用中", GenerationPhase.ApplyingWallpaper, generatingItem.id, trigger)
            val applyResult = wallpaperService.applyWallpaper(
                imageReference = imageUriString,
                updateLockScreen = config.updateLockScreen,
            )

            if (applyResult.isSuccess) {
                val success = generatingItem.copy(
                    status = GenerationStatus.Success,
                    errorSummary = null,
                    appliedImageUri = imageUriString,
                    usedCalendarEvents = usedEvents,
                    usedNewsTopics = adoptedNews,
                    usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                    generatedPrompt = generatedPrompt,
                )
                historyService.updateHistoryItem(success)
                if (config.showNotification) {
                    notificationHelper.showSuccessNotification(imageUriString)
                }
                postProgress(100, "処理完了", GenerationPhase.Completed, success.id, trigger)
                success
            } else {
                val errorSummary = "壁紙の適用に失敗しました: ${applyResult.exceptionOrNull()?.message ?: "不明なエラー"}"
                val failure = generatingItem.copy(
                    status = GenerationStatus.Failure,
                    errorSummary = errorSummary,
                    appliedImageUri = imageUriString,
                    usedCalendarEvents = usedEvents,
                    usedNewsTopics = adoptedNews,
                    usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                    generatedPrompt = generatedPrompt,
                )
                historyService.updateHistoryItem(failure)
                if (config.showNotification) {
                    notificationHelper.showFailureNotification(errorSummary)
                }
                postProgress(99, "生成に失敗しました", GenerationPhase.Failed, failure.id, trigger)
                failure
            }
        } catch (e: Exception) {
            Log.e(TAG, "生成に失敗しました", e)
            val failure = generatingItem.copy(
                status = GenerationStatus.Failure,
                errorSummary = e.message ?: "不明なエラー",
                appliedImageUri = appliedImageUri,
                usedCalendarEvents = usedEvents,
                usedNewsTopics = usedNews,
                usedPrompt = resumable?.usedPrompt ?: config.userPrompt.takeIf { it.isNotEmpty() },
                generatedPrompt = generatedPrompt,
            )
            historyService.updateHistoryItem(failure)
            if (config.showNotification) {
                notificationHelper.showFailureNotification(failure.errorSummary ?: "不明なエラー")
            }
            postProgress(99, "生成に失敗しました", GenerationPhase.Failed, failure.id, trigger)
            failure
        } finally {
            temporaryImagePath?.let {
                runCatching { File(it).delete() }
            }
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

    // 実進捗が取れない短い待機処理を、指定範囲内の合成進捗として通知する
    private suspend fun <T> runWithSyntheticProgress(
        startPercent: Int,
        maxBeforeCompletionPercent: Int,
        message: String,
        phase: GenerationPhase,
        historyId: String?,
        trigger: GenerationTrigger,
        block: suspend () -> T,
    ): T = coroutineScope {
        var emitted = startPercent.coerceAtMost(maxBeforeCompletionPercent)
        postProgress(emitted, message, phase, historyId, trigger)
        val progressJob = launch {
            while (isActive && emitted < maxBeforeCompletionPercent) {
                delay(1_000)
                emitted = (emitted + 1).coerceAtMost(maxBeforeCompletionPercent)
                postProgress(emitted, message, phase, historyId, trigger)
            }
        }
        try {
            block()
        } finally {
            progressJob.cancelAndJoin()
        }
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
    }
}
