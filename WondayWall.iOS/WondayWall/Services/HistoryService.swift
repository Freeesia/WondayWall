import Foundation

// 生成履歴の読み書きを担当するサービス
final class HistoryService {
    private let historyURL: URL
    // 保存する最大件数
    private let maxItems = 100

    init() {
        historyURL = FileHelper.appDataDirectory.appendingPathComponent("history.json")
    }

    // 全履歴を読み込む
    func load() -> [HistoryItem] {
        FileHelper.load([HistoryItem].self, from: historyURL) ?? []
    }

    // 先頭に1件追加してから保存する
    func append(_ item: HistoryItem) {
        var history = load()
        history.insert(item, at: 0)
        if history.count > maxItems {
            history = Array(history.prefix(maxItems))
        }
        FileHelper.save(history, to: historyURL)
    }

    // 指定した ID の履歴を削除する
    func delete(_ id: UUID) {
        var history = load()
        history.removeAll { $0.id == id }
        FileHelper.save(history, to: historyURL)
    }

    // 最後に成功した（スキップでない）履歴を返す
    func getLastSuccessfulGenerated() -> HistoryItem? {
        load().first { $0.isSuccess && !$0.isSkipped }
    }
}
