import Foundation
import Observation

// ホーム画面の ViewModel
@MainActor
@Observable
final class HomeViewModel {
    var isGenerating = false
    var latestHistory: HistoryItem?
    var showShareSheet = false
    var showInstructions = false
    var showSaveSuccess = false
    var errorMessage: String?

    private let environment: AppEnvironment

    var latestImagePath: String? {
        latestHistory?.imagePath.flatMap { FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        loadLatestHistory()
    }

    func loadLatestHistory() {
        latestHistory = environment.historyService.getLastSuccessfulGenerated()
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
    }

    // 写真に保存する
    func saveToPhotos() async {
        guard let path = latestImagePath else { return }
        do {
            try await environment.wallpaperService.saveToPhotos(imagePath: path)
            showSaveSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // 壁紙設定手順を表示する
    func showWallpaperInstructions() {
        showInstructions = true
    }
}
