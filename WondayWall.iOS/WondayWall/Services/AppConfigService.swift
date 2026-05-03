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

    // 現在の設定（監視可能）
    private(set) var config: AppConfig

    // Google AI API キー（Keychain に保存）
    var googleAiApiKey: String {
        didSet {
            Self.keychain[Self.apiKeyKeychainKey] = googleAiApiKey.isEmpty ? nil : googleAiApiKey
        }
    }

    init() {
        config = Defaults[.appConfig]
        googleAiApiKey = Self.keychain[Self.apiKeyKeychainKey] ?? ""
    }

    // 設定を保存する
    func save() {
        Defaults[.appConfig] = config
    }

    // クロージャで設定を変更してから保存する
    func update(_ block: (inout AppConfig) -> Void) {
        block(&config)
        save()
    }
}
