import Foundation
import Observation

// 履歴画面の ViewModel
@MainActor
@Observable
final class HistoryViewModel {
    var items: [HistoryItem] = []
    var isRegenerating = false
    var errorMessage: String?

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        loadHistory()
    }

    func loadHistory() {
        items = environment.historyService.load()
    }

    // 指定した履歴を削除する
    func delete(_ item: HistoryItem) {
        environment.historyService.delete(item.id)
        loadHistory()
    }

    // 同じ条件で再生成する（手動生成と同じフロー）
    func regenerate() async {
        guard !isRegenerating else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        let result = await environment.coordinator.runManual()
        if !result.isSuccess {
            errorMessage = result.errorSummary ?? "再生成に失敗しました"
        }
        loadHistory()
    }
}
