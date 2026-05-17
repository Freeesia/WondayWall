import Foundation
import Observation

// 履歴画面の ViewModel
@MainActor
@Observable
final class HistoryViewModel {
    var items: [HistoryItem] = []

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
}
