import Foundation
import Observation
import Defaults
import KeychainAccess

// Defaults キー定義
extension Defaults.Keys {
    static let appConfig = Key<AppConfig>("appConfig", default: AppConfig())
}

// Defaults.Serializable への適合（Codable を橋渡しする）
extension AppConfig: Defaults.Serializable {}

// 設定の読み書きを担当するサービス
@Observable
final class AppConfigService {
    private static let keychain = Keychain(service: "com.studiofreesia.wondaywall")
    private static let apiKeyKeychainKey = "google_ai_api_key"

    // 設定変更時に UI や Widget へ反映するための通知フック
    var onConfigurationChanged: (() -> Void)?

    // 現在の設定（監視可能）
    private(set) var config: AppConfig

    // Google AI API キー（Keychain に保存）
    var googleAiApiKey: String {
        didSet {
            // 空文字は Keychain から削除し、秘密情報を残さない
            Self.keychain[Self.apiKeyKeychainKey] = googleAiApiKey.isEmpty ? nil : googleAiApiKey
            onConfigurationChanged?()
        }
    }

    // DEBUG 時のみ有効: デバッグ専用設定
    #if DEBUG
    var debugConfig: DebugConfig {
        didSet { Defaults[.debugConfig] = debugConfig }
    }
    #endif

    init() {
        config = Defaults[.appConfig]
        googleAiApiKey = Self.keychain[Self.apiKeyKeychainKey] ?? ""
        #if DEBUG
        debugConfig = Defaults[.debugConfig]
        #endif
    }

    // 設定を保存する
    func save() {
        Defaults[.appConfig] = config
        onConfigurationChanged?()
    }

    // クロージャで設定を変更してから保存する
    func update(_ block: (inout AppConfig) -> Void) {
        block(&config)
        save()
    }

    // 起動時補完生成を実行できる最低限の設定が揃っているかを判定する
    // APIキー未設定、かつ入力コンテキストが一切ない場合は未設定とみなす
    func hasMinimumConfigurationForStartupGeneration() -> Bool {
        let hasApiKey = !googleAiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasApiKey else { return false }

        let hasCalendar = !config.targetCalendarIds.isEmpty
        let hasRss = !config.rssSources.isEmpty
        let hasUserPrompt = !config.userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasCalendar || hasRss || hasUserPrompt
    }
}
