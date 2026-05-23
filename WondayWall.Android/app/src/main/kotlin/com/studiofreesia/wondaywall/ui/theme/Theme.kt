package com.studiofreesia.wondaywall.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// WondayWall ライトテーマカラー
private val LightColors = lightColorScheme(
    primary = Color(0xFF1A73E8),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD2E4FF),
    onPrimaryContainer = Color(0xFF001B47),
    secondary = Color(0xFF535F70),
    onSecondary = Color.White,
    background = Color(0xFFF8F9FA),
    surface = Color.White,
    surfaceVariant = Color(0xFFDFE2EB),
    error = Color(0xFFBA1A1A),
    onError = Color.White,
)

// WondayWall ダークテーマカラー
private val DarkColors = darkColorScheme(
    primary = Color(0xFFA6C8FF),
    onPrimary = Color(0xFF003070),
    primaryContainer = Color(0xFF00449F),
    onPrimaryContainer = Color(0xFFD2E4FF),
    secondary = Color(0xFFB9C7DB),
    onSecondary = Color(0xFF233240),
    background = Color(0xFF1A1C1E),
    surface = Color(0xFF1A1C1E),
    surfaceVariant = Color(0xFF3F4759),
    error = Color(0xFFFFB4AB),
    onError = Color(0xFF690005),
)

// アプリ全体に適用する Material3 テーマ
@Composable
fun WondayWallTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colorScheme = if (darkTheme) DarkColors else LightColors
    MaterialTheme(
        colorScheme = colorScheme,
        content = content,
    )
}
