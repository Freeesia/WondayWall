package com.studiofreesia.wondaywall.services

import android.content.Context
import com.studiofreesia.wondaywall.models.DebugConfig
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// デバッグ専用設定をまとめて保存するサービス
class DebugConfigService(context: Context) {
    private val sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    fun getConfig(): DebugConfig {
        val jsonText = sharedPreferences.getString(KEY_CONFIG_JSON, null) ?: return DebugConfig()
        return runCatching {
            json.decodeFromString<DebugConfig>(jsonText).normalized()
        }.getOrDefault(DebugConfig())
    }

    fun saveConfig(config: DebugConfig) {
        sharedPreferences.edit()
            .putString(KEY_CONFIG_JSON, json.encodeToString(config.normalized()))
            .apply()
    }

    fun updateConfig(transform: (DebugConfig) -> DebugConfig): DebugConfig {
        val updated = transform(getConfig()).normalized()
        saveConfig(updated)
        return updated
    }

    companion object {
        private const val PREFS_NAME = "wondaywall_debug_prefs"
        private const val KEY_CONFIG_JSON = "debug_config_json"
    }
}
