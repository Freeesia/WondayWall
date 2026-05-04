import Foundation
import KeychainAccess

// Keychain へのシンプルなアクセスラッパー（KeychainAccess ライブラリを使用）
enum KeychainHelper {
    private static let keychain = Keychain(service: "com.studiofreesia.wondaywall")

    // 文字列を Keychain に保存する
    static func save(_ value: String, forKey key: String) {
        keychain[key] = value
    }

    // Keychain から文字列を取得する（存在しない場合は nil）
    static func load(forKey key: String) -> String? {
        keychain[key]
    }

    // Keychain からエントリを削除する
    static func delete(forKey key: String) {
        keychain[key] = nil
    }
}
