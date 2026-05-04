import Foundation
import Photos
import UIKit

// 生成画像を壁紙として利用できる状態にするサービス
// iOS では通常アプリから壁紙を直接変更できないため、写真ライブラリ保存・共有・設定手順表示を行う
final class WallpaperService {
    // 指定した画像パスの画像が存在するかを確認する
    func imageExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // 写真ライブラリへの追加権限が得られているかを確認する
    func canSaveToPhotos() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    // 生成画像を写真ライブラリに保存する
    func saveToPhotos(imagePath: String) async throws {
        guard let image = UIImage(contentsOfFile: imagePath) else {
            throw NSError(
                domain: "WondayWall", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "画像ファイルが見つかりません: \(imagePath)"]
            )
        }

        let authorized = await canSaveToPhotos()
        guard authorized else {
            throw NSError(
                domain: "WondayWall", code: 403,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "写真ライブラリへのアクセス権限がありません。設定アプリから許可してください。"
                ]
            )
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }

    // 共有シートを表示するための UIActivityViewController を生成して返す
    @MainActor
    func makeShareController(imagePath: String) -> UIActivityViewController? {
        guard let image = UIImage(contentsOfFile: imagePath) else { return nil }
        let items: [Any] = [image]
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    // 壁紙設定手順のテキストを返す
    func wallpaperInstructions() -> String {
        """
        壁紙の設定手順:
        1. 「写真に保存」で写真ライブラリに保存します
        2. 「設定」アプリを開きます
        3. 「壁紙」→「+壁紙を追加」を選択します
        4. 「写真」から保存した画像を選択します
        5. ホーム画面・ロック画面に設定します
        """
    }
}
