package com.studiofreesia.wondaywall.ui.util

import android.net.Uri
import java.io.File

// 画像 URI を Coil に渡せるモデルへ変換する
fun imageReferenceModel(reference: String): Any {
    val uri = Uri.parse(reference)
    return if (uri.scheme.isNullOrEmpty()) File(reference) else uri
}

// content URI は存在確認が重いため、表示側の画像ローダーに委ねる
fun canDisplayImageReference(reference: String): Boolean {
    val uri = Uri.parse(reference)
    return when (uri.scheme) {
        null, "" -> File(reference).exists()
        "file" -> uri.path?.let { File(it).exists() } ?: false
        else -> true
    }
}
