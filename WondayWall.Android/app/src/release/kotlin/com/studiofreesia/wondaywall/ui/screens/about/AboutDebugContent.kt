package com.studiofreesia.wondaywall.ui.screens.about

import androidx.compose.runtime.Composable
import com.studiofreesia.wondaywall.services.AppConfigService
import com.studiofreesia.wondaywall.services.GenerationCoordinator
import com.studiofreesia.wondaywall.services.AiService
import com.studiofreesia.wondaywall.services.TaskSchedulerService

@Composable
internal fun AboutDebugEntry(onShowDebugInfo: () -> Unit) = Unit

@Composable
internal fun AboutDebugScreen(
    appConfigService: AppConfigService,
    generationCoordinator: GenerationCoordinator,
    aiService: AiService,
    taskSchedulerService: TaskSchedulerService,
    onBack: () -> Unit,
    onClose: () -> Unit,
) = Unit
