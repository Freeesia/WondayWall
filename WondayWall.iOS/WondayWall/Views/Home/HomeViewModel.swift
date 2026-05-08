import Foundation
import Observation
import UIKit
import Combine

// ホーム画面の ViewModel
@MainActor
@Observable
final class HomeViewModel {
    var latestHistory: HistoryItem?
    // ローカルに解決済みの画像フルパス（非同期復元後に更新される）
    var latestImage: UIImage?
    var showInstructions = false
    var errorMessage: String?

    private let environment: AppEnvironment
    private var cancellables: Set<AnyCancellable> = []

    init(environment: AppEnvironment) {
        self.environment = environment
        loadLatestHistory()
        // AppEnvironment.isGenerating を購読して生成完了時に履歴を再読み込みする
        environment.$isGenerating
            .receive(on: RunLoop.main)
            .sink { [weak self] generating in
                guard let self, !generating else { return }
                self.loadLatestHistory()
                Task<Void, Never> { @MainActor in await self.refreshLatestImage() }
            }
            .store(in: &cancellables)
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
        let result = await environment.coordinator.runManual()
        if !result.isSuccess && result.status != .generating {
            errorMessage = result.errorSummary ?? "生成に失敗しました"
        }
    }

    // 壁紙設定手順を表示する
    func showWallpaperInstructions() {
        showInstructions = true
    }
}
