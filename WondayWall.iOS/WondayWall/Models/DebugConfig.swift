#if DEBUG
import Foundation
import Defaults

// デバッグ専用設定モデル
struct DebugConfig: Codable {
    // Google AI をダミー実装に切り替える（切り替えは次回起動時に反映）
    var useDummyGoogleAiService: Bool = false
    // ダミー実装でのプロンプト生成遅延秒数
    var dummyPromptDelaySeconds: Int = 180
    // ダミー実装での画像生成遅延秒数
    var dummyImageDelaySeconds: Int = 600
}

// Defaults キー定義
extension Defaults.Keys {
    static let debugConfig = Key<DebugConfig>("debugConfig", default: DebugConfig())
}

// Defaults.Serializable への適合（Codable を橋渡しする）
extension DebugConfig: Defaults.Serializable {}
#endif
