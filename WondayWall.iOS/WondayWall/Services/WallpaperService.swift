import Foundation
import Photos
import UIKit

// 生成画像を壁紙として利用できる状態にするサービス
// iOS では通常アプリから壁紙を直接変更できないため、写真ライブラリ保存・共有・設定手順表示を行う
final class WallpaperService {
    private static let albumName = "WondayWall"

    // 指定した画像パスの画像が存在するかを確認する
    func imageExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // 写真ライブラリへのフルアクセス権限が得られているかを確認する
    func canSaveToPhotos() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // 生成画像を写真ライブラリに保存する（カメラロールのみ・手動保存用）
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

    // 生成画像を WondayWall アルバムに保存し、前回のアセットをアルバムから外す
    // 戻り値: 作成したアセットの識別子（次回の previousAssetId に使う）
    @discardableResult
    func saveToPhotosAlbum(imagePath: String, previousAssetId: String?) async throws -> String {
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

        let album = try await getOrCreateAlbum(named: Self.albumName)

        // アセット作成とアルバムへの追加を1トランザクションで行う
        var assetId: String = ""
        try await PHPhotoLibrary.shared().performChanges {
            // 新しいアセットを作成する
            let createRequest = PHAssetChangeRequest.creationRequestForAsset(from: image)
            let assetPlaceholder = createRequest.placeholderForCreatedAsset
            let albumChangeRequest = PHAssetCollectionChangeRequest(for: album)

            // アルバムに新しいアセットを追加する
            if let placeholder = assetPlaceholder {
                albumChangeRequest?.addAssets([placeholder] as NSArray)
                assetId = placeholder.localIdentifier
            }

            // 前回のアセットをアルバムから外す（削除しない）
            if let prevId = previousAssetId {
                let prevFetch = PHAsset.fetchAssets(withLocalIdentifiers: [prevId], options: nil)
                if prevFetch.count > 0 {
                    albumChangeRequest?.removeAssets(prevFetch)
                }
            }
        }

        return assetId
    }

    // WondayWall アルバムを取得または作成する
    private func getOrCreateAlbum(named title: String) async throws -> PHAssetCollection {
        // 既存アルバムを検索する
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", title)
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,
            options: fetchOptions
        )
        if let existing = collections.firstObject {
            return existing
        }

        // アルバムが存在しない場合は作成する
        var createdAlbumId: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(
                withTitle: title)
            createdAlbumId = request.placeholderForCreatedAssetCollection.localIdentifier
        }

        guard let albumId = createdAlbumId else {
            throw NSError(
                domain: "WondayWall", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "アルバムの作成に失敗しました。"]
            )
        }

        let created = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [albumId], options: nil)
        guard let album = created.firstObject else {
            throw NSError(
                domain: "WondayWall", code: 500,
                userInfo: [NSLocalizedDescriptionKey: "作成したアルバムが見つかりません。"]
            )
        }
        return album
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
        1. 「写真」アプリの「WondayWall」アルバムを開きます
        2. 最新の壁紙画像を選択します
        3. 共有ボタン →「壁紙として使用」を選択します
        4. ホーム画面・ロック画面に設定します
        """
    }
}
