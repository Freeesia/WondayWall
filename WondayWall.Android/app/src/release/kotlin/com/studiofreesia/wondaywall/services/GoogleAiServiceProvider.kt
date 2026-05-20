package com.studiofreesia.wondaywall.services

import android.content.Context
import java.io.File

// Release ビルドでは常に実 API 実装を使う
object GoogleAiServiceProvider {
    fun create(
        context: Context,
        appConfigService: AppConfigService,
        filesDir: File,
    ): GoogleAiServiceProtocol = GoogleAiService(appConfigService, filesDir)
}
