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
    // 壁紙生成確認シート
    var showGenerationSheet = false
    var sheetEvents: [CalendarEventItem] = []
    var sheetNews: [NewsTopicItem] = []
    var isLoadingSheetData = false

    private let environment: AppEnvironment
    private var cancellables: Set<AnyCancellable> = []

    init(environment: AppEnvironment) {
        self.environment = environment
        loadLatestHistory()
        // AppEnvironment.generationProgress を購読して生成完了時に履歴を再読み込みする
        environment.$generationProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] progress in
                guard let self, progress == nil else { return }
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

    // 壁紙生成確認シートを表示するためにデータを読み込む
    @MainActor
    func loadSheetData() async {
        guard !isLoadingSheetData else { return }
        isLoadingSheetData = true
        defer { isLoadingSheetData = false }
        sheetEvents = environment.contextService.fetchCalendarEvents()
        sheetNews = await environment.contextService.fetchNews()
    }

    // ウィジェット起動要求から、現在も生成可能な場合だけ確認シートを開く
    @MainActor
    func openGenerationSheetIfStillAllowed(slotStartedAt: Date) async {
        guard !environment.isGenerating else { return }
        let config = environment.configService.config
        guard config.hasCompletedInitialSetup else { return }
        guard !environment.configService.googleAiApiKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
        else { return }

        let currentSlot = ScheduleHelper.getLatestScheduledSlotAtOrBefore(
            Date(),
            schedule: config.schedule
        )
        guard abs(currentSlot.timeIntervalSince(slotStartedAt)) < 1 else { return }

        if let lastCompleted = environment.historyService.getLastCompletedRun(),
           lastCompleted.executedAt >= currentSlot {
            loadLatestHistory()
            return
        }

        showGenerationSheet = true
    }

    // 手動生成を実行する
    func generate() async {
        showGenerationSheet = false
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
