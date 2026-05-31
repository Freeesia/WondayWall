import Foundation
import Photos
import UIKit

enum WallpaperSettingsOpenResult {
    case wallpaperSettings
    case settingsRoot
    case failed
}

// 生成画像を壁紙として利用できる状態にするサービス
// iOS では通常アプリから壁紙を直接変更できないため、写真ライブラリ保存・共有・設定手順表示を行う
final class WallpaperService {
    private static let albumName = "WondayWall"

    // 指定した画像パスの画像が存在するかを確認する
    func imageExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // 写真ライブラリへのフルアクセス権限が得られているかを確認する
    func hasPhotoLibraryAccess() -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // 写真ライブラリへのフルアクセス権限を要求する
    func canSaveToPhotos() async -> Bool {
        if hasPhotoLibraryAccess() { return true }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    // 生成画像を写真ライブラリに保存する（カメラロールのみ・手動保存用）
    func saveToPhotos(image: UIImage) async throws {
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
    // maxCount: アルバムの最大保存枚数（超過分は古い順に削除）
    // 戻り値: 作成したアセットの識別子（次回の previousAssetId に使う）
    @discardableResult
    func saveToPhotosAlbum(imagePath: String, previousAssetId: String?, maxCount: Int = 10) async throws -> String {
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
        }

        // アルバムの枚数が上限を超えた場合は古い順にアルバムから外す（ライブラリからは削除しない）
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let assets = PHAsset.fetchAssets(in: album, options: fetchOptions)
        let excess = assets.count - maxCount
        if excess > 0 {
            var toRemove: [PHAsset] = []
            for i in 0..<excess { toRemove.append(assets[i]) }
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetCollectionChangeRequest(for: album)?.removeAssets(toRemove as NSArray)
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
    func makeShareController(image: UIImage) -> UIActivityViewController {
        return UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    // 非公式URLスキームで壁紙設定または設定トップを開く
    @MainActor
    func openWallpaperSettings() async -> WallpaperSettingsOpenResult {
        if await openSettingsURL("App-Prefs:root=Wallpaper") {
            return .wallpaperSettings
        }
        if await openSettingsURL("App-Prefs:root") {
            return .settingsRoot
        }
        return .failed
    }

    @MainActor
    private func openSettingsURL(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    // Photos ライブラリからアセット ID で画像を読み込む
    // targetSize: サムネイル用に小さいサイズを指定可能（PHImageManagerMaximumSize でフルサイズ）
    func loadImage(assetId: String, targetSize: CGSize = PHImageManagerMaximumSize) async -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = assets.firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.version = .current
            // フルサイズは高品質を待つ、サムネイルは最初の結果を使う
            options.deliveryMode =
                (targetSize == PHImageManagerMaximumSize) ? .highQualityFormat : .opportunistic
            var resumed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard !resumed else { return }
                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if targetSize == PHImageManagerMaximumSize && isDegraded { return }
                resumed = true
                continuation.resume(returning: image)
            }
        }
    }

    // 壁紙設定手順のテキストを返す
    func wallpaperInstructions() -> String {
        """
        写真シャッフル壁紙の設定手順:
        1. 写真アプリで「WondayWall」アルバムに画像が保存されていることを確認します
        2. iOSの設定アプリを開きます
        3. 「壁紙」を開きます
        4. 「新しい壁紙を追加」を選択します
        5. 「写真シャッフル」を選択します
        6. 「WondayWall」アルバムを選択します
        7. シャッフル頻度を選択します
        8. 「アルバムを使用」を選択します
        9. 必要に応じて「壁紙を両方に設定」を選択します
        """
    }
}
