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
    // 上限を超えた古い履歴は削除する
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

    // 指定した ID の履歴を更新する（生成中→完了への遷移に使用）
    func update(_ item: HistoryItem) {
        var history = load()
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index] = item
        } else {
            history.insert(item, at: 0)
        }
        FileHelper.save(history, to: historyURL)
    }

    // 最後に成功した（スキップでない）履歴を返す
    func getLastSuccessfulGenerated() -> HistoryItem? {
        load().first { $0.isSuccess && !$0.isSkipped }
    }

    // 最後に完了した生成試行を返す
    // スケジュール枠の消費判定では成功・失敗のどちらも実行済みとして扱う
    func getLastCompletedRun() -> HistoryItem? {
        load()
            .filter { $0.status != .generating }
            .sorted { $0.executedAt > $1.executedAt }
            .first
    }
}
