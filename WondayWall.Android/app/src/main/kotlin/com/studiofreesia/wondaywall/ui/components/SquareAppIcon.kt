package com.studiofreesia.wondaywall.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.R

// Adaptive icon のマスクを避け、アプリ内では四角いアイコンとして表示する。
@Composable
fun SquareAppIcon(
    modifier: Modifier = Modifier,
    size: Dp = 80.dp,
) {
    Box(
        modifier = modifier
            .size(size)
            .background(Color(0xFFE91E63)),
    ) {
        Image(
            painter = painterResource(R.mipmap.ic_launcher_foreground),
            contentDescription = "WondayWall",
            modifier = Modifier.fillMaxSize(),
            contentScale = ContentScale.Fit,
        )
    }
}
