import Foundation

// 生成履歴の読み書きを担当するサービス
final class HistoryService {
    private let historyURL: URL
    // 保存する最大件数
    private let maxItems = 100

    // 履歴変更時に Widget 表示状態を更新するための通知フック
    var onHistoryChanged: (() -> Void)?

    init(repairInterruptedGeneration: Bool = true) {
        FileHelper.migrateHistoryToSharedContainerIfNeeded()
        historyURL = FileHelper.historyFileURL
        guard repairInterruptedGeneration else { return }
        // プロセス起動時に生成中のまま残っている履歴を確認する
        // 画像 API 呼び出し済み（generatingImageRequested）の場合はスロット消費済みとして failure に変換する
        // それ以外（generating / generatingPromptReady）は再試行可能なので generating のまま残す：
        // getLastCompletedRun() は isGenerating を除外するためスロットが未消費のまま維持され、
        // 次の起動・FG 復帰時に runScheduledIfNeeded() が再試行を実行する
        if let latest = load().first, latest.status == .generatingImageRequested {
            let failed = HistoryItem(
                id: latest.id,
                executedAt: latest.executedAt,
                status: .failure,
                usedCalendarEvents: latest.usedCalendarEvents,
                usedNewsTopics: latest.usedNewsTopics,
                usedPrompt: latest.usedPrompt,
                errorSummary: "アプリが強制終了したため生成が中断されました",
                photoAssetId: latest.photoAssetId
            )
            update(failed)
        }
    }

    // 全履歴を読み込む
    func load() -> [HistoryItem] {
        FileHelper.load([HistoryItem].self, from: historyURL) ?? []
    }

    // 新しい実行日時順の履歴を返す
    func loadNewestFirst() -> [HistoryItem] {
        load().sorted { $0.executedAt > $1.executedAt }
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
        onHistoryChanged?()
    }

    // 指定した ID の履歴を削除する
    func delete(_ id: UUID) {
        var history = load()
        history.removeAll { $0.id == id }
        FileHelper.save(history, to: historyURL)
        onHistoryChanged?()
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
        onHistoryChanged?()
    }

    // 最後に成功した（スキップでない）履歴を返す
    func getLastSuccessfulGenerated() -> HistoryItem? {
        loadNewestFirst().first { $0.isSuccess && !$0.isSkipped }
    }

    // 最後に完了した生成試行を返す
    // スケジュール枠の消費判定では成功・失敗のどちらも実行済みとして扱う
    func getLastCompletedRun() -> HistoryItem? {
        loadNewestFirst()
            .filter { !$0.isGenerating }
            .first
    }

    // 指定スロット以降に完了した生成試行を返す
    func getCompletedRun(since slotStartedAt: Date) -> HistoryItem? {
        loadNewestFirst().first {
            !$0.isGenerating && $0.executedAt >= slotStartedAt
        }
    }

    // 指定スロットが処理済みかを返す
    func isSlotProcessed(startedAt slotStartedAt: Date) -> Bool {
        guard let lastCompleted = getLastCompletedRun() else { return false }
        return lastCompleted.executedAt >= slotStartedAt
    }

    // Widget などの表示に使う履歴を返す
    // 現在スロットに画像がなければ、直近成功履歴の画像へフォールバックする。
    func getLatestDisplayCandidate(since slotStartedAt: Date) -> HistoryItem? {
        if let slotHistory = getCompletedRun(since: slotStartedAt),
           slotHistory.photoAssetId != nil {
            return slotHistory
        }
        return getLastSuccessfulGenerated()
    }

    // Widget などの表示に使うニュースを返す
    // スキップ履歴にニュースがない場合は直近成功履歴のニュースへフォールバックする。
    func getDisplayNewsTopics(since slotStartedAt: Date) -> [NewsTopicItem] {
        if let slotNews = getCompletedRun(since: slotStartedAt)?.usedNewsTopics,
           !slotNews.isEmpty {
            return slotNews
        }
        return getLastSuccessfulGenerated()?.usedNewsTopics ?? []
    }

    // Widget などの表示に使う予定を返す
    // スキップ履歴に予定がない場合は直近成功履歴の予定へフォールバックする。
    func getDisplayCalendarEvents(since slotStartedAt: Date) -> [CalendarEventItem] {
        if let slotEvents = getCompletedRun(since: slotStartedAt)?.usedCalendarEvents,
           !slotEvents.isEmpty {
            return slotEvents
        }
        return getLastSuccessfulGenerated()?.usedCalendarEvents ?? []
    }

    // 保存済み履歴から指定 ID の予定を探す
    func findCalendarEvent(id: String) -> CalendarEventItem? {
        loadNewestFirst()
            .compactMap { $0.usedCalendarEvents }
            .flatMap { $0 }
            .first { $0.id == id }
    }

    // プロンプト生成済み・画像 API 未呼び出しの再開可能な履歴を返す
    // generatingPromptReady: 画像 API を呼ぶ前に kill されたため再開可能
    func getGeneratingWithPrompt() -> HistoryItem? {
        load().first { $0.status == .generatingPromptReady }
    }

    // プロンプト生成前（最初から再試行可能）の履歴を返す
    // generating: 旧データ互換も含め、プロンプト生成前に kill された状態
    func getPendingGeneratingItem() -> HistoryItem? {
        load().first { $0.status == .generating }
    }
}
