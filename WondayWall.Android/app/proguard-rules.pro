# WondayWall プロジェクト固有の ProGuard ルール
# デフォルトのルールはビルドツールが自動生成するため、ここでは追加ルールのみ記載する。

# Google GenAI SDK は Jackson で SDK モデルを JSON 変換するため、
# R8 によるクラス削除・難読化でデシリアライズが壊れないよう保持する。
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod,MethodParameters
-keep class com.google.genai.JsonSerializable { *; }
-keep class com.google.genai.JsonSerializable$* { *; }
-keep class com.google.genai.errors.** { *; }
-keep class com.google.genai.types.** { *; }
# Jackson TypeReference の匿名クラスは generic superclass 情報が実行時に必要。
-keep class * extends com.fasterxml.jackson.core.type.TypeReference { *; }

# Google GenAI の service entry が shading 前の KotlinModule を参照するため、R8 の警告を抑制する。
-dontwarn com.fasterxml.jackson.module.kotlin.**
