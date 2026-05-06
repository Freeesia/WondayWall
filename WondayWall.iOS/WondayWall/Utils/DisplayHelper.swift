import UIKit

// デバイス画面情報から Gemini API パラメータを決定するヘルパー
enum DisplayHelper {
    // gemini-3.1-flash-image-preview がサポートする縦長比率と 2K 時のピクセルサイズ
    // 参考: https://ai.google.dev/gemini-api/docs/image-generation#3.1-flash-image-preview
    // ratio label → (w/h 比率, 2K サイズ px)
    private static let supportedPortraitRatios: [(label: String, whRatio: Double)] = [
        ("9:16", 9.0 / 16.0),   // 1536×2752
        ("2:3",  2.0 / 3.0),    // 1696×2528
        ("3:4",  3.0 / 4.0),    // 1792×2400
        ("4:5",  4.0 / 5.0),    // 1856×2304
    ]

    // 現在のデバイス画面のネイティブピクセルサイズを返す
    // UIScreen.main は iOS 16 で deprecated のため UIWindowScene 経由で取得する
    @MainActor
    static func nativeScreenSize() -> CGSize {
        let screen =
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
            ?? UIScreen.main
        let bounds = screen.nativeBounds
        // nativeBounds は常に縦長で返るとは限らないため、縦長に正規化する
        let w = min(bounds.width, bounds.height)
        let h = max(bounds.width, bounds.height)
        return CGSize(width: w, height: h)
    }

    // ネイティブ画面サイズから最も近い Gemini 対応比率文字列を返す
    static func closestGeminiAspectRatio(for size: CGSize) -> String {
        let ratio = size.width / size.height  // 縦長前提なので < 1
        return supportedPortraitRatios
            .min(by: { abs($0.whRatio - ratio) < abs($1.whRatio - ratio) })?
            .label ?? "9:16"
    }
}
