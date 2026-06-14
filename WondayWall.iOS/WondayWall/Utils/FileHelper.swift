import Foundation

// ファイルパスとJSON読み書きのユーティリティ
enum FileHelper {
    // アプリサポートディレクトリ（設定・履歴保存先）
    static var appDataDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("WondayWall")
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    // App Group 共有ディレクトリ（アプリ本体と Widget Extension で共有するデータ保存先）
    static var sharedDataDirectory: URL {
        let dir: URL
        if let appGroupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "WondayWallAppGroupIdentifier"
        ) as? String,
           let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
           ) {
            dir = containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("WondayWall", isDirectory: true)
        } else {
            dir = appDataDirectory
        }
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    // App Group 共有キャッシュディレクトリ（消えてもよい一時表示データ用）
    static var sharedCacheDirectory: URL {
        let dir: URL
        if let appGroupIdentifier = Bundle.main.object(
            forInfoDictionaryKey: "WondayWallAppGroupIdentifier"
        ) as? String,
           let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
           ) {
            dir = containerURL
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
                .appendingPathComponent("WondayWall", isDirectory: true)
        } else {
            let cacheDirectory = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first!
            dir = cacheDirectory.appendingPathComponent("WondayWall", isDirectory: true)
        }
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    static var historyFileURL: URL {
        sharedDataDirectory.appendingPathComponent("history.json")
    }

    static var legacyHistoryFileURL: URL {
        appDataDirectory.appendingPathComponent("history.json")
    }

    static func migrateHistoryToSharedContainerIfNeeded() {
        let sourceURL = legacyHistoryFileURL
        let destinationURL = historyFileURL
        guard sourceURL != destinationURL,
              FileManager.default.fileExists(atPath: sourceURL.path),
              !FileManager.default.fileExists(atPath: destinationURL.path)
        else { return }

        try? FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.copyItem(at: sourceURL, to: destinationURL)
    }

    // 壁紙画像の保存ディレクトリ
    static var wallpaperDirectory: URL {
        let dir = appDataDirectory.appendingPathComponent("wallpapers")
        try? FileManager.default.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        return dir
    }

    // タイムスタンプ付きの画像ファイルパスを生成する
    static func getImageFilePath(extension ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        // 端末のロケール・カレンダー設定（和暦など）の影響を受けないよう固定する
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        let name = "wallpaper_\(formatter.string(from: Date())).\(ext)"
        return wallpaperDirectory.appendingPathComponent(name)
    }

    // JSON ファイルからデコードして返す（失敗時は nil）
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    // JSON エンコードしてファイルに書き込む
    static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
