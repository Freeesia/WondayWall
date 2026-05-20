package com.studiofreesia.wondaywall.services

import android.content.Context
import java.io.File

// Debug ビルドではデバッグ設定に応じて実 API / ダミー実装を切り替える
object GoogleAiServiceProvider {
    fun create(
        context: Context,
        appConfigService: AppConfigService,
        filesDir: File,
    ): GoogleAiServiceProtocol {
        val debugConfigService = DebugConfigService(context)
        return if (debugConfigService.getConfig().useDummyGoogleAiService) {
            DummyGoogleAiService(debugConfigService, filesDir)
        } else {
            GoogleAiService(appConfigService, filesDir)
        }
    }

    fun currentServiceName(service: GoogleAiServiceProtocol): String =
        if (service is DummyGoogleAiService) "Dummy" else "Live"

    fun nextLaunchServiceName(configService: DebugConfigService): String =
        if (configService.getConfig().useDummyGoogleAiService) "Dummy" else "Live"
}
