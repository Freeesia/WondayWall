# WondayWall プロジェクト固有の ProGuard ルール
# デフォルトのルールはビルドツールが自動生成するため、ここでは追加ルールのみ記載する。

# kotlinx.serialization — JSON モデルクラスの難読化を防ぐ
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.studiofreesia.wondaywall.**$$serializer { *; }
-keepclassmembers class com.studiofreesia.wondaywall.** {
    *** Companion;
}
-keepclasseswithmembers class com.studiofreesia.wondaywall.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Tink — 暗号化ライブラリのリフレクション利用を保護する
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# google-genai SDK — リフレクションで使用される内部クラスを保護する
-keep class com.google.genai.** { *; }
-dontwarn com.google.genai.**

# rssparser — KMP ライブラリのリフレクション利用を保護する
-keep class com.prof18.rssparser.** { *; }
-dontwarn com.prof18.rssparser.**

# jsoup — HTML パーサーの内部クラスを保護する
-keep class org.jsoup.** { *; }
-dontwarn org.jsoup.**
