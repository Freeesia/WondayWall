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
