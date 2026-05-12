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
