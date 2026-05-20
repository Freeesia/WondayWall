package com.studiofreesia.wondaywall.services

import java.io.File
import kotlinx.coroutines.runBlocking

// Debug / Preview ビルドでは起動時設定に応じて実サービスとダミーAIサービスを切り替える
internal fun bindAiService(
    appConfigService: AppConfigService,
    filesDir: File,
): AiService {
    val config = runBlocking { appConfigService.getConfig() }
    return if (config.debugConfig.useDummyAiService) {
        DummyAiService(appConfigService, filesDir)
    } else {
        GoogleAiService(appConfigService, filesDir)
    }
}
