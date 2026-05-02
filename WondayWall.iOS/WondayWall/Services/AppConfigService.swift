import Foundation
import Observation

// 設定の読み書きを担当するサービス
@Observable
final class AppConfigService {
    private let configURL: URL

    // 現在の設定（監視可能）
    private(set) var config: AppConfig

    init() {
        configURL = FileHelper.appDataDirectory.appendingPathComponent("config.json")
        config = FileHelper.load(AppConfig.self, from: configURL) ?? AppConfig()
    }

    // 設定をファイルに保存する
    func save() {
        FileHelper.save(config, to: configURL)
    }

    // クロージャで設定を変更してから保存する
    func update(_ block: (inout AppConfig) -> Void) {
        block(&config)
        save()
    }
}
