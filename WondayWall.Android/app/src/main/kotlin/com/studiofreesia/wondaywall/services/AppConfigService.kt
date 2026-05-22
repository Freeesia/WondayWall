package com.studiofreesia.wondaywall.services

import android.content.Context
import android.util.Base64
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.google.crypto.tink.Aead
import com.google.crypto.tink.KeyTemplates
import com.google.crypto.tink.integration.android.AndroidKeysetManager
import com.studiofreesia.wondaywall.models.AppConfig
import com.studiofreesia.wondaywall.models.DebugConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

// DataStore のシングルトンインスタンス（複数作成を防ぐためトップレベルに宣言）
private val Context.appConfigDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "app_config"
)

// アプリ設定の読み書きを担当するサービス
class AppConfigService(private val context: Context) {

    private val configJsonKey = stringPreferencesKey("config_json")
    private val debugConfigJsonKey = stringPreferencesKey("debug_config_json")

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    // Tink Aead プリミティブ（遅延初期化、Android Keystore でラップされた AES256-GCM キーを使用）
    private val aead: Aead by lazy {
        val keysetHandle = AndroidKeysetManager.Builder()
            .withSharedPref(context, API_KEY_KEYSET_NAME, KEYSET_PREFS_NAME)
            .withKeyTemplate(KeyTemplates.get("AES256_GCM"))
            .withMasterKeyUri(MASTER_KEY_URI)
            .build()
            .keysetHandle
        keysetHandle.getPrimitive(Aead::class.java)
    }

    // API キーを除いた設定変更を監視できる Flow（API キーは Tink で別途管理）
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

    // Debug ビルド用の追加設定を監視する Flow
    private val debugConfigFlow: Flow<DebugConfig> = context.appConfigDataStore.data
        .catch { emit(emptyPreferences()) }
        .map { prefs ->
            val jsonStr = prefs[debugConfigJsonKey] ?: return@map DebugConfig()
            try {
                json.decodeFromString<DebugConfig>(jsonStr).normalized()
            } catch (e: Exception) {
                DebugConfig()
            }
        }

    // 現在の設定を取得する（Tink で復号した API キーを含む）
    suspend fun getConfig(): AppConfig {
        val config = configFlow.first()
        val apiKey = getGoogleAiApiKey()
        return config.copy(googleAiApiKey = apiKey)
    }

    // 設定全体を保存する（API キーは Tink で暗号化、それ以外は DataStore に保存）
    suspend fun saveConfig(config: AppConfig) {
        // API キーが含まれている場合は暗号化して別途保存する
        if (config.googleAiApiKey.isNotEmpty()) {
            saveGoogleAiApiKey(config.googleAiApiKey)
        }
        // DataStore には API キーを除いた設定を保存する（平文保存しない）
        val configWithoutKey = config.copy(googleAiApiKey = "")
        val jsonStr = json.encodeToString(configWithoutKey)
        context.appConfigDataStore.edit { prefs ->
            prefs[configJsonKey] = jsonStr
        }
    }

    // 設定の一部を更新する
    suspend fun updateConfig(transform: (AppConfig) -> AppConfig) {
        val current = getConfig()
        saveConfig(transform(current))
    }

    // Debug ビルド用の追加設定を取得する
    suspend fun getDebugConfig(): DebugConfig =
        debugConfigFlow.first()

    // Debug ビルド用の追加設定を保存する
    suspend fun saveDebugConfig(config: DebugConfig) {
        val jsonStr = json.encodeToString(config.normalized())
        context.appConfigDataStore.edit { prefs ->
            prefs[debugConfigJsonKey] = jsonStr
        }
    }

    // Google AI API キーを Tink で暗号化して SharedPreferences に保存する
    suspend fun saveGoogleAiApiKey(key: String) = withContext(Dispatchers.IO) {
        try {
            val encrypted = aead.encrypt(key.toByteArray(Charsets.UTF_8), null)
            val encoded = Base64.encodeToString(encrypted, Base64.DEFAULT)
            context.getSharedPreferences(KEYSET_PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(ENCRYPTED_API_KEY_PREF, encoded)
                .apply()
        } catch (e: Exception) {
            // 暗号化に失敗した場合はログに記録する（キーは保存されない）
            Log.e(TAG, "API キーの暗号化に失敗しました", e)
        }
    }

    // Tink で復号した Google AI API キーを返す（未保存の場合は空文字）
    suspend fun getGoogleAiApiKey(): String = withContext(Dispatchers.IO) {
        try {
            val encoded = context.getSharedPreferences(KEYSET_PREFS_NAME, Context.MODE_PRIVATE)
                .getString(ENCRYPTED_API_KEY_PREF, null) ?: return@withContext ""
            val encrypted = Base64.decode(encoded, Base64.DEFAULT)
            String(aead.decrypt(encrypted, null), Charsets.UTF_8)
        } catch (e: Exception) {
            // 復号に失敗した場合はログに記録して空文字を返す（キーストアの不整合などで発生しうる）
            Log.e(TAG, "API キーの復号に失敗しました", e)
            ""
        }
    }

    companion object {
        private const val TAG = "AppConfigService"
        // Tink キーセットの保存先（SharedPreferences）
        private const val KEYSET_PREFS_NAME = "wondaywall_crypto_prefs"
        // キーセットの識別子
        private const val API_KEY_KEYSET_NAME = "wondaywall_api_key_keyset"
        // Android Keystore のマスターキー URI
        private const val MASTER_KEY_URI = "android-keystore://wondaywall_api_key_mk"
        // 暗号化済み API キーを保存する SharedPreferences キー
        private const val ENCRYPTED_API_KEY_PREF = "encrypted_api_key"
    }
}
