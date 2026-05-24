package com.studiofreesia.wondaywall.services

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.core.app.NotificationCompat
import com.studiofreesia.wondaywall.MainActivity
import com.studiofreesia.wondaywall.models.GenerationProgress
import java.io.File

// 通知送信ヘルパー（GenerationCoordinator から使用する）
class NotificationHelper(private val context: Context) {

    companion object {
        const val CHANNEL_SUCCESS = "generation_success"
        const val CHANNEL_FAILURE = "generation_failure"
        const val CHANNEL_PROGRESS = "generation_progress"
        const val NOTIFICATION_ID_PROGRESS = 1001
        private const val NOTIFICATION_ID_SUCCESS = 1002
        private const val NOTIFICATION_ID_FAILURE = 1003
        private const val NOTIFICATION_IMAGE_MAX_SIZE = 1024
    }

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    // 生成完了通知を送る
    fun showSuccessNotification(imageReference: String?) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val picture = imageReference?.let { decodeNotificationBitmap(it) }
        val builder = NotificationCompat.Builder(context, CHANNEL_SUCCESS)
            .setSmallIcon(android.R.drawable.ic_menu_gallery)
            .setContentTitle(context.getString(com.studiofreesia.wondaywall.R.string.notification_success_title))
            .setContentText(context.getString(com.studiofreesia.wondaywall.R.string.notification_success_text))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)

        if (picture != null) {
            builder
                .setLargeIcon(picture)
                .setStyle(
                    NotificationCompat.BigPictureStyle()
                        .bigPicture(picture)
                        .bigLargeIcon(null as Bitmap?)
                )
        }

        val notification = builder
            .build()
        notificationManager.notify(NOTIFICATION_ID_SUCCESS, notification)
    }

    // 生成失敗通知を送る
    fun showFailureNotification(errorMessage: String) {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            context, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_FAILURE)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setContentTitle(context.getString(com.studiofreesia.wondaywall.R.string.notification_failure_title))
            .setContentText(errorMessage)
            .setStyle(NotificationCompat.BigTextStyle().bigText(errorMessage))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        notificationManager.notify(NOTIFICATION_ID_FAILURE, notification)
    }

    // 生成進行中通知（ForegroundInfo 用）
    fun buildProgressNotification(progress: GenerationProgress? = null): android.app.Notification {
        val percent = progress?.percent?.coerceIn(0, 100) ?: 0
        val message = progress?.message
            ?: context.getString(com.studiofreesia.wondaywall.R.string.notification_generating_text)
        return NotificationCompat.Builder(context, CHANNEL_PROGRESS)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(context.getString(com.studiofreesia.wondaywall.R.string.notification_generating_title))
            .setContentText(message)
            .setProgress(100, percent, progress == null)
            .setOngoing(true)
            .build()
    }

    private fun decodeNotificationBitmap(imageReference: String): Bitmap? {
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            openInputStream(imageReference)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                null
            } else {
                val options = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(bounds, NOTIFICATION_IMAGE_MAX_SIZE)
                }
                openInputStream(imageReference)?.use { BitmapFactory.decodeStream(it, null, options) }
            }
        } catch (_: Exception) {
            null
        }
    }

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

    private fun calculateInSampleSize(bounds: BitmapFactory.Options, maxSize: Int): Int {
        var sampleSize = 1
        var width = bounds.outWidth
        var height = bounds.outHeight
        while (width / 2 >= maxSize || height / 2 >= maxSize) {
            width /= 2
            height /= 2
            sampleSize *= 2
        }
        return sampleSize.coerceAtLeast(1)
    }

    private fun String.toUriOrNull(): Uri? {
        val uri = Uri.parse(this)
        return if (uri.scheme.isNullOrEmpty()) null else uri
    }
}
