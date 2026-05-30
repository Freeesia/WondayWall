package com.studiofreesia.wondaywall.ui.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.studiofreesia.wondaywall.R

// Adaptive icon の白い角を避け、アプリ内では透過 PNG をそのまま表示する。
@Composable
fun SquareAppIcon(
    modifier: Modifier = Modifier,
    size: Dp = 80.dp,
) {
    Image(
        painter = painterResource(R.drawable.app_icon),
        contentDescription = "WondayWall",
        modifier = modifier
            .size(size),
        contentScale = ContentScale.Fit,
    )
}
