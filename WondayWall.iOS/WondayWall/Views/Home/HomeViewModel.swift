import Foundation
import Observation
import UIKit

// ホーム画面の ViewModel
@MainActor
@Observable
final class HomeViewModel {
    var isGenerating = false
    var latestHistory: HistoryItem?
    // ローカルに解決済みの画像フルパス（非同期復元後に更新される）
    var latestImage: UIImage?
    var showInstructions = false
    var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        loadLatestHistory()
    }

    func loadLatestHistory() {
        latestHistory = environment.historyService.getLastSuccessfulGenerated()
        Task<Void, Never> { @MainActor in await self.refreshLatestImage() }
    }

    // Photos から最新画像を非同期で読み込む
    func refreshLatestImage() async {
        guard let item = latestHistory, let assetId = item.photoAssetId else {
            latestImage = nil
            return
        }
        latestImage = await environment.wallpaperService.loadImage(assetId: assetId)
    }

    // 手動生成を実行する
    func generate() async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let result = await environment.coordinator.runManual()
        latestHistory = result.isSuccess ? result : latestHistory
        if !result.isSuccess {
            errorMessage = result.errorSummary ?? "生成に失敗しました"
        }
        await refreshLatestImage()
    }

    // 壁紙設定手順を表示する
    func showWallpaperInstructions() {
        showInstructions = true
    }
}
