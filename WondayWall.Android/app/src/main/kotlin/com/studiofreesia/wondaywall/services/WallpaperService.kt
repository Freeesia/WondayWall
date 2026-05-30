package com.studiofreesia.wondaywall.services

import android.Manifest
import android.app.WallpaperManager
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import androidx.core.content.ContextCompat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.coroutines.resume

// 壁紙の適用・保存・共有を担当するサービス
class WallpaperService(private val context: Context) {

    // 生成画像をホーム画面（および設定次第でロック画面）に壁紙として適用する
    suspend fun applyWallpaper(imageReference: String, updateLockScreen: Boolean): Result<Unit> =
        withContext(Dispatchers.IO) {
            val bitmap = decodeBitmap(imageReference)
                ?: return@withContext Result.failure(
                    IllegalArgumentException("壁紙画像の読み込みに失敗しました: $imageReference")
                )

            return@withContext try {
                val wallpaperManager = WallpaperManager.getInstance(context)

                // ホーム画面へ適用
                wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_SYSTEM)

                // updateLockScreen が有効な場合はロック画面にも適用する
                if (updateLockScreen) {
                    wallpaperManager.setBitmap(bitmap, null, true, WallpaperManager.FLAG_LOCK)
                }
                Result.success(Unit)
            } catch (e: Exception) {
                Result.failure(e)
            } finally {
                bitmap.recycle()
            }
        }

    // 生成画像を写真領域の WondayWall フォルダに保存する
    suspend fun saveToPhotos(filePath: String): Result<Uri> = withContext(Dispatchers.IO) {
        val file = File(filePath)
        if (!file.exists()) {
            return@withContext Result.failure(
                IllegalArgumentException("保存するファイルが見つかりません: $filePath")
            )
        }

        return@withContext try {
            val extension = imageExtension(file)
            val mimeType = mimeTypeForExtension(extension)
            val fileName = "WondayWall_${System.currentTimeMillis()}.$extension"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                Result.success(saveToMediaStore(file, fileName, mimeType))
            } else {
                if (!hasLegacyWritePermission()) {
                    throw SecurityException("写真領域への書き込み権限がありません。")
                }
                Result.success(saveToLegacyPictures(file, fileName, mimeType))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // 画像共有用の Intent を返す（Activity から startActivity で使用する）
    fun buildShareIntent(imageReference: String): Intent? {
        val contentUri = shareUriForReference(imageReference) ?: return null
        return Intent(Intent.ACTION_SEND).apply {
            type = mimeTypeForReference(imageReference)
            putExtra(Intent.EXTRA_STREAM, contentUri)
            clipData = ClipData.newUri(context.contentResolver, "WondayWall", contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }

    private fun decodeBitmap(imageReference: String) =
        openInputStream(imageReference)?.use { BitmapFactory.decodeStream(it) }

    private fun openInputStream(imageReference: String) =
        when (val uri = imageReference.toUriOrNull()) {
            null -> {
                val file = File(imageReference)
                if (file.exists()) file.inputStream() else null
            }
            else -> when (uri.scheme) {
                "content" -> context.contentResolver.openInputStream(uri)
                "file" -> uri.path?.let { File(it) }?.takeIf { it.exists() }?.inputStream()
                else -> null
            }
        }

    private fun saveToMediaStore(file: File, fileName: String, mimeType: String): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(
                MediaStore.Images.Media.RELATIVE_PATH,
                Environment.DIRECTORY_PICTURES + "/$ALBUM_NAME"
            )
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val resolver = context.contentResolver
        val imageUri = resolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("MediaStore への挿入に失敗しました。")

        try {
            resolver.openOutputStream(imageUri)?.use { outputStream ->
                file.inputStream().use { inputStream -> inputStream.copyTo(outputStream) }
            } ?: throw IllegalStateException("写真領域への書き込みストリームを開けませんでした。")

            val publishedValues = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            resolver.update(imageUri, publishedValues, null, null)
            return imageUri
        } catch (e: Exception) {
            resolver.delete(imageUri, null, null)
            throw e
        }
    }

    @Suppress("DEPRECATION")
    private suspend fun saveToLegacyPictures(file: File, fileName: String, mimeType: String): Uri {
        val picturesDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            ALBUM_NAME
        ).also { it.mkdirs() }
        val destFile = uniqueFile(picturesDir, fileName)
        file.copyTo(destFile, overwrite = false)
        return scanFile(destFile, mimeType)
    }

    private suspend fun scanFile(file: File, mimeType: String): Uri =
        suspendCancellableCoroutine { continuation ->
            MediaScannerConnection.scanFile(
                context,
                arrayOf(file.absolutePath),
                arrayOf(mimeType),
            ) { _, uri ->
                if (continuation.isActive) {
                    continuation.resume(uri ?: Uri.fromFile(file))
                }
            }
        }

    private fun shareUriForReference(imageReference: String): Uri? {
        val uri = imageReference.toUriOrNull()
        if (uri?.scheme == "content") return uri
        val file = when (uri?.scheme) {
            "file" -> uri.path?.let { File(it) }
            null -> File(imageReference)
            else -> null
        }?.takeIf { it.exists() } ?: return null
        return FileProvider.getUriForFile(
            context,
            "${context.packageName}.provider",
            file,
        )
    }

    private fun mimeTypeForReference(imageReference: String): String {
        val uri = imageReference.toUriOrNull()
        if (uri?.scheme == "content") {
            return context.contentResolver.getType(uri) ?: "image/*"
        }
        val file = when (uri?.scheme) {
            "file" -> uri.path?.let { File(it) }
            null -> File(imageReference)
            else -> null
        }
        return file?.let { mimeTypeForExtension(imageExtension(it)) } ?: "image/*"
    }

    private fun hasLegacyWritePermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED

    private fun imageExtension(file: File): String {
        val extension = file.extension.lowercase()
        return when (extension) {
            "jpg", "jpeg", "png", "webp" -> extension
            else -> "jpg"
        }
    }

    private fun mimeTypeForExtension(extension: String): String =
        MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
            ?: when (extension) {
                "png" -> "image/png"
                "webp" -> "image/webp"
                else -> "image/jpeg"
            }

    private fun uniqueFile(directory: File, fileName: String): File {
        val baseName = fileName.substringBeforeLast('.', fileName)
        val extension = fileName.substringAfterLast('.', "")
        var candidate = File(directory, fileName)
        var index = 1
        while (candidate.exists()) {
            val suffix = if (extension.isEmpty()) "_$index" else "_$index.$extension"
            candidate = File(directory, "$baseName$suffix")
            index += 1
        }
        return candidate
    }

    private fun String.toUriOrNull(): Uri? {
        val uri = Uri.parse(this)
        return if (uri.scheme.isNullOrEmpty()) null else uri
    }

    companion object {
        private const val ALBUM_NAME = "WondayWall"
    }
}
