package com.studiofreesia.wondaywall.ui.components

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Language
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale

// URLのファビコンを表示するビュー
// iOS版と同じく Google Favicon Service から取得した画像をファイルキャッシュして表示する。
@Composable
fun FaviconIcon(
    url: String?,
    modifier: Modifier = Modifier,
    size: Dp = 28.dp,
) {
    val context = LocalContext.current
    var faviconFile by remember(url) { mutableStateOf<File?>(null) }

    LaunchedEffect(url) {
        faviconFile = FaviconCache.loadFile(context.applicationContext, url)
    }

    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(6.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Default.Language,
            contentDescription = null,
            modifier = Modifier.size(size * 0.58f),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (faviconFile != null) {
            AsyncImage(
                model = ImageRequest.Builder(context)
                    .data(faviconFile)
                    .build(),
                contentDescription = null,
                modifier = Modifier
                    .matchParentSize()
                    .padding(4.dp),
                contentScale = ContentScale.Fit,
            )
        }
    }
}

// ファビコンのファイルキャッシュ
private object FaviconCache {
    suspend fun loadFile(context: Context, urlString: String?): File? = withContext(Dispatchers.IO) {
        val host = normalizedHost(urlString) ?: return@withContext null
        val cacheFile = cacheFile(context, host)
        if (cacheFile.exists() && cacheFile.length() > 0L) {
            return@withContext cacheFile
        }

        val faviconUrl = faviconUrl(host)
        runCatching {
            val connection = (URL(faviconUrl).openConnection() as HttpURLConnection).apply {
                connectTimeout = 10_000
                readTimeout = 10_000
                instanceFollowRedirects = true
            }
            try {
                val status = connection.responseCode
                if (status !in 200 until 300) return@runCatching null
                val bytes = connection.inputStream.use { it.readBytes() }
                if (BitmapFactory.decodeByteArray(bytes, 0, bytes.size) == null) {
                    return@runCatching null
                }

                cacheFile.parentFile?.mkdirs()
                val tempFile = File(cacheFile.parentFile, "${cacheFile.name}.tmp")
                tempFile.writeBytes(bytes)
                if (!tempFile.renameTo(cacheFile)) {
                    tempFile.copyTo(cacheFile, overwrite = true)
                    tempFile.delete()
                }
                cacheFile
            } finally {
                connection.disconnect()
            }
        }.getOrNull()
    }

    private fun normalizedHost(urlString: String?): String? {
        if (urlString.isNullOrBlank()) return null
        return runCatching {
            Uri.parse(urlString).host?.lowercase(Locale.US)
        }.getOrNull()
    }

    private fun faviconUrl(host: String): String =
        Uri.Builder()
            .scheme("https")
            .authority("www.google.com")
            .path("s2/favicons")
            .appendQueryParameter("domain", host)
            .appendQueryParameter("sz", "64")
            .build()
            .toString()

    private fun cacheFile(context: Context, host: String): File {
        val safeName = buildString {
            host.forEach { char ->
                if (char.isLetterOrDigit()) append(char) else append('_')
            }
        }
        return File(File(context.cacheDir, "favicons"), "$safeName.png")
    }
}
