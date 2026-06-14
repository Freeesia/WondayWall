#if DEBUG
import Foundation
import Defaults

// デバッグ専用設定モデル
struct DebugConfig: Codable {
    // ダミーAIサービスに切り替える（切り替えは次回起動時に反映）
    var useDummyAiService: Bool = false
    // ダミー実装でのプロンプト生成遅延秒数
    var dummyPromptDelaySeconds: Int = 180
    // ダミー実装での画像生成遅延秒数
    var dummyImageDelaySeconds: Int = 600
    // ダミー実装で生成コンテキストに含めるニュース件数
    var dummyNewsCount: Int = 4

    func normalized() -> DebugConfig {
        var config = self
        config.dummyPromptDelaySeconds = min(max(config.dummyPromptDelaySeconds, Self.minDelaySeconds), Self.maxDelaySeconds)
        config.dummyImageDelaySeconds = min(max(config.dummyImageDelaySeconds, Self.minDelaySeconds), Self.maxDelaySeconds)
        config.dummyNewsCount = min(max(config.dummyNewsCount, Self.minNewsCount), Self.maxNewsCount)
        return config
    }

    static let minDelaySeconds = 1
    static let maxDelaySeconds = 3600
    static let minNewsCount = 0
    static let maxNewsCount = 20
}

// Defaults キー定義
extension Defaults.Keys {
    static let debugConfig = Key<DebugConfig>("debugConfig", default: DebugConfig())
}

// Defaults.Serializable への適合（Codable を橋渡しする）
extension DebugConfig: Defaults.Serializable {}
#endif
