package com.studiofreesia.wondaywall.services

import android.app.WallpaperManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

// 壁紙の適用・保存・共有を担当するサービス
class WallpaperService(private val context: Context) {

    // 生成画像をホーム画面（および設定次第でロック画面）に壁紙として適用する
    suspend fun applyWallpaper(filePath: String, updateLockScreen: Boolean): Result<Unit> =
        withContext(Dispatchers.IO) {
            val file = File(filePath)
            if (!file.exists()) {
                return@withContext Result.failure(
                    IllegalArgumentException("壁紙ファイルが見つかりません: $filePath")
                )
            }

            val bitmap = BitmapFactory.decodeFile(filePath)
                ?: return@withContext Result.failure(
                    IllegalArgumentException("壁紙ファイルの読み込みに失敗しました: $filePath")
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

    // 生成画像をギャラリー（MediaStore）に保存する
    suspend fun saveToGallery(filePath: String): Result<Uri> = withContext(Dispatchers.IO) {
        val file = File(filePath)
        if (!file.exists()) {
            return@withContext Result.failure(
                IllegalArgumentException("保存するファイルが見つかりません: $filePath")
            )
        }

        return@withContext try {
            val fileName = "WondayWall_${System.currentTimeMillis()}.jpg"
            val uri: Uri

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Android 10以上: MediaStore 経由で保存する
                val contentValues = ContentValues().apply {
                    put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                    put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
                    put(
                        MediaStore.Images.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_PICTURES + "/WondayWall"
                    )
                }
                val imageUri = context.contentResolver.insert(
                    MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
                    contentValues
                ) ?: throw Exception("MediaStore への挿入に失敗しました。")

                context.contentResolver.openOutputStream(imageUri)?.use { outputStream ->
                    file.inputStream().use { it.copyTo(outputStream) }
                }
                uri = imageUri
            } else {
                // Android 9以下: 直接ファイルに書き込む
                val picturesDir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
                    "WondayWall"
                )
                picturesDir.mkdirs()
                val destFile = File(picturesDir, fileName)
                file.copyTo(destFile, overwrite = true)

                // MediaStore に通知して写真一覧に反映させる
                @Suppress("DEPRECATION")
                android.media.MediaScannerConnection.scanFile(
                    context,
                    arrayOf(destFile.absolutePath),
                    arrayOf("image/jpeg"),
                    null
                )
                uri = Uri.fromFile(destFile)
            }
            Result.success(uri)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    // 画像共有用の Intent を返す（Activity から startActivity で使用する）
    fun buildShareIntent(filePath: String): Intent? {
        val file = File(filePath)
        if (!file.exists()) return null

        val contentUri = FileProvider.getUriForFile(
            context,
            "${context.packageName}.provider",
            file,
        )
        return Intent(Intent.ACTION_SEND).apply {
            type = "image/*"
            putExtra(Intent.EXTRA_STREAM, contentUri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
    }
}
