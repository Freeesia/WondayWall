package com.studiofreesia.wondaywall.services

import java.io.File

// Release ビルドでは常に実 API 実装を使う
internal fun bindAiService(
    appConfigService: AppConfigService,
    filesDir: File,
): AiService = GoogleAiService(appConfigService, filesDir)
