import CoreGraphics

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

    // 保存済みの画面サイズから Gemini 対応比率文字列を返す
    static func closestGeminiAspectRatio(
        screenPixelWidth: Double?,
        screenPixelHeight: Double?
    ) -> String {
        guard let width = screenPixelWidth,
              let height = screenPixelHeight,
              width > 0,
              height > 0
        else {
            return "9:16"
        }

        let size = CGSize(width: min(width, height), height: max(width, height))
        return closestGeminiAspectRatio(for: size)
    }

    // ネイティブ画面サイズから最も近い Gemini 対応比率文字列を返す
    private static func closestGeminiAspectRatio(for size: CGSize) -> String {
        let ratio = size.width / size.height  // 縦長前提なので < 1
        return supportedPortraitRatios
            .min(by: { abs($0.whRatio - ratio) < abs($1.whRatio - ratio) })?
            .label ?? "9:16"
    }
}
