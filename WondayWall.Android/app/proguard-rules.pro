# WondayWall プロジェクト固有の ProGuard ルール
# デフォルトのルールはビルドツールが自動生成するため、ここでは追加ルールのみ記載する。

# Google GenAI の service entry が shading 前の KotlinModule を参照するため、R8 の警告を抑制する。
-dontwarn com.fasterxml.jackson.module.kotlin.**
