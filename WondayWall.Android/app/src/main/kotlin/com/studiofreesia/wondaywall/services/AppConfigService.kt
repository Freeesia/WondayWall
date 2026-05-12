package com.studiofreesia.wondaywall.services

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.studiofreesia.wondaywall.models.AppConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// DataStore のシングルトンインスタンス（複数作成を防ぐためトップレベルに宣言）
private val Context.appConfigDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "app_config"
)

// アプリ設定の読み書きを担当するサービス
class AppConfigService(private val context: Context) {

    private val configJsonKey = stringPreferencesKey("config_json")

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    // 設定変更を監視できる Flow
    val configFlow: Flow<AppConfig> = context.appConfigDataStore.data
        .catch { emit(emptyPreferences()) }
        .map { prefs ->
            val jsonStr = prefs[configJsonKey] ?: return@map AppConfig()
            try {
                json.decodeFromString<AppConfig>(jsonStr)
            } catch (e: Exception) {
                AppConfig()
            }
        }

    // 現在の設定を一度だけ取得する
    suspend fun getConfig(): AppConfig = configFlow.first()

    // 設定全体を保存する
    suspend fun saveConfig(config: AppConfig) {
        val jsonStr = json.encodeToString(config)
        context.appConfigDataStore.edit { prefs ->
            prefs[configJsonKey] = jsonStr
        }
    }

    // 設定の一部を更新する
    suspend fun updateConfig(transform: (AppConfig) -> AppConfig) {
        val current = getConfig()
        saveConfig(transform(current))
    }
}
